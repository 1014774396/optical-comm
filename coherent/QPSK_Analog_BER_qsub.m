function BER = QPSK_Analog_BER_qsub(CPR, ReceiverType, fiberLength, Modulator, ModBW, linewidth, ideal, Delayps)
%% Estimate BER of a QPSK system based on analog receiver
% - CPR: carrier phase recovery type: {'EPLL': electric PLL, 'OPLL':
% optical PLL}
% - ReceiverType: {'logic': based on XOR operations, 'costas': based on 
% Costas loop, which requries multipliers}
% - fiberLength: fiber length in km
% - Modulator: either 'MZM' or 'SiPhotonics'
% - ModBW: modulator bandwidth in GHz. Only used when Modulator == 'SiPhotonics'
% - linewidth: laser linewidth in kHz
% - ideal: whether analog components are assumed ideal
% - Delay: additional loop delay in samples. Note this depends on sampling
% rate to emulatae continuous time

addpath f/
addpath analog/
addpath ../f/
addpath ../apd/
addpath ../soa/
addpath ../mpam/

%
filename = sprintf('results/Analog_QPSK_BER_%s_%s_L=%skm_%s_BW=%sGHz_linewidth=%skHz_ideal=%s_delay=%sps',...
        upper(CPR), ReceiverType, fiberLength, Modulator, ModBW, linewidth, ideal, Delayps)

% convert inputs to double (on cluster inputs are passed as strings)
if ~all(isnumeric([fiberLength ModBW linewidth ideal Delayps]))
    fiberLength = 1e3*str2double(fiberLength);
    ModBW = 1e9*str2double(ModBW);
    linewidth = 1e3*str2double(linewidth);
    ideal = logical(str2double(ideal));
    Delayps = 1e-12*round(str2double(Delayps));
end

%% ======================== Simulation parameters =========================
sim.Nsymb = 2^17; % Number of symbols in montecarlo simulation
sim.Mct = 12;    % Oversampling ratio to simulate continuous time 
sim.BERtarget = 1.8e-4; 
sim.Ndiscard = 256; % number of symbols to be discarded from the begining and end of the sequence 
sim.N = sim.Mct*sim.Nsymb; % number points in 'continuous-time' simulation
sim.Rb = 2*112e9; % Bit rate
sim.ModFormat = 'QAM';                                                     % either 'QAM' or 'DPSK'
sim.M    = 4;                                                              % QAM order
sim.pulse = 'NRZ';                                                         % Transmitter pulse shape ('NRZ')
sim.Npol = 2;                                                              % number of polarizations
sim.Modulator = Modulator;                                                     % Modulator type: {'MZM': limited by loss and velocity mismatch, 'SiPhotonics' : limited by parasitics (2nd-order response)}
sim.Rs = sim.Rb/(sim.Npol*log2(sim.M))                                     % Symbol Rate

% Simulation
sim.RIN = true; 
sim.PMD = false;
sim.phase_noise = true;
sim.preAmp = false;
sim.stopWhenBERreaches0 = true;                                            % whether simulation should stop when counted BER reaches 0 for the first time
sim.save = true;                                                           % save data dump

%% Time and frequency
sim.fs = sim.Rs*sim.Mct;  % sampling frequency for 'continuous-time' simulation

dt = 1/sim.fs;
t = 0:dt:(sim.N-1)*dt;
df = 1/(dt*sim.N);
f = -sim.fs/2:df:sim.fs/2-df;

sim.t = t;
sim.f = f;

%% Plots
Plots = containers.Map();                                                   % List of figures 
Plots('BER')                  = 0; 
Plots('Eye diagram') = 0;
Plots('Channel frequency response') = 0;
Plots('Constellations') = 0;
Plots('Diff group delay')       = 0;
Plots('Phase error') = 0;
Plots('EPLL phase error') = 0;
sim.Plots = Plots;
sim.shouldPlot = @(x) sim.Plots.isKey(x) && sim.Plots(x);

%% ===================== Transmitter Electric Filter ====================== 
Tx.filt = design_filter('bessel', 5, 0.7*sim.Rs/(sim.fs/2));               % design_filter(type, order, normalized cutoff frequency)
Tx.Delx  = 0;                                                               % Delay of x pol. in pol. mux. (symbol intervals)
Tx.Dely  = 0;                                                               % Delay of y pol. in pol. mux. (symbol intervals)

%% ========================== Transmitter Laser =========================== 
% Laser constructor: laser(lambda (nm), PdBm (dBm), RIN (dB/Hz), linewidth (Hz), frequency offset (Hz))
% lambda : wavelength (nm)
% PdBm : output power (dBm)
% RIN : relative intensity noise (dB/Hz)
% linewidth : laser linewidth (Hz)
% freqOffset : frequency offset with respect to wavelength (Hz)
Tx.Laser = laser(1250e-9, 0, -150, linewidth, 0);

%% ============================= Modulator ================================
if strcmpi(sim.Modulator, 'MZM') 
    %% Mach-Zehnder (limited by velocity mismatch and loss)
    % K. P. Ho, Phase-Modulated Optical Communication Systems. New York: Springer, 2005.
    % Parameters are the taken from Milad's code to result in a MZM with
    % bandwidth of about 50 GHz
    omega = 2*pi*f;
    c = 3e8;
    Mod.Vpi = 4.5;                                                         % Modulator switching voltage (V)
    ratio      = 0.98;                                                     % velocity mismatch ratio         
    n_r        = 2.15;                                                     % refractive index of coplanar-waveguide (CPW) for TM input light
    n_m        = n_r*ratio;                                                % 
    Mod.d_12   = (n_m -n_r)/c;                                             % Velocity mismatch difference between the optical and electrical waveguides
    Mod.a      = 0.01*100*sqrt(abs(omega)/2/pi*1e-9);                      % Microwave attenuation coefficient (electrode loss)
    Mod.L      = 0.05;                                                     % Interaction length 
    Mod.Hel    = (1-exp(Mod.L*(-Mod.a + 1j*Mod.d_12*omega)))./...          % Freq. response of the optical modulator limited by elec. loss and velocity mismatch
                    (Mod.a-1j*Mod.d_12*omega)/Mod.L;
    Mod.Hel(isnan(Mod.Hel)) = 1;                                           % Mod.Hel(f=0) is NaN  
elseif strcmpi(sim.Modulator, 'SiPhotonics') 
    %% Si Photonics (limited by parasitics, 2nd-order response)
    Mod.BW = ModBW;
    Mod.fc = Mod.BW/sqrt(sqrt(2)-1); % converts to relaxation frequency
    Mod.grpdelay = 2/(2*pi*Mod.fc);  % group delay of second-order filter in seconds
    Mod.Hel = exp(1j*2*pi*f*Mod.grpdelay)./(1 + 2*1j*f/Mod.fc - (f/Mod.fc).^2);  % laser freq. resp. (unitless) f is frequency vector (Hz)
end
Tx.Mod = Mod;                                                              % optical modulator

%% =============================== Fiber ==================================
% Constructor: fiber(L, att(lamb) (optional), D(lamb) (optional)) 
% L : fiber length (m)
% att(lamb) : function handle of attenuation (att) at wavelength (lamb),
% deafault is att(lamb) = 0 dB/km
% D(lamb) : function handle of dispersion (D) at wavelength (lamb) in ps/(kmnm),
% default is D(lamb) = SSMF with lamb0 @ 1310 ps/(kmnm)
Fiber = fiber(fiberLength);
Fiber.PMD = sim.PMD;                                                       % whether to similate PMD
Fiber.meanDGDps = 0.1;                                                     % Mean DGD (ps)
Fiber.PMD_section_length = 1e3;                                            % Controls number of sections to simulate PMD (m)

%% ======================== Optical Amplifier =============================
% Constructor: soa(GaindB, NF, lamb, maxGain (optional))
% GaindB : Gain in dB
% NF : Noise figure in dB
% lamb : wavelength in m
% maxGain = maximum amplifier gain in dB, default is Inf
Amp = soa(20, 7, Tx.Laser.lambda);
% Note: class soa can be used for any amplifier, since it essentially 
% characterizes the amplifier in terms of gain and noise figure only

%% ======================= Local Oscilator ================================
Rx.LO = Tx.Laser;                                                          % Copy parameters from TX laser
Rx.LO.PdBm = 9.8;                                                           % Total local oscillator power (dBm)
Rx.LO.freqOffset = 0;                                                    % Frequency shift with respect to transmitter laser in Hz

%% ============================ Hybrid ====================================
% polarization splitting --------------------------------------------------
Rx.PolSplit.sig  = 'PBS';                                                   % pbs: polarization beamsplitter
Rx.PolSplit.LO   = 'PBS';                                                   % 3dB: 3-dB coupler     
Rx.PolSplit.Rext = 30;                                                      % PBS extinction ratio (dB), default = 30
Rx.PolSplit.R3dB = 1/2;                                                     % power splitting ratio of nominally 3-dB coupler (system performance should be insensitive to this parameter)
% 90-degree hybrid, same parameter for two polarizations ------------------
Rx.Hybrid.fS = 0.5;                                                         % power splitting ratio for signal coupler (W/W), default = 0.5
Rx.Hybrid.fL = 0.5;                                                         % power splitting ratio for LO coupler (W/W), default = 0.5
Rx.Hybrid.fI = 0.5;                                                         % power splitting ratio for in-phase coupler (W/W), default = 0.5
Rx.Hybrid.fQ = 0.5;                                                         % power splitting ratio for quadrature coupler (W/W), default = 0.5
Rx.Hybrid.tauIps = 0;                                                       % delay in in-phase branch (ps), default = 0
Rx.Hybrid.tauQps = 0;                                                       % delay in quadrature branch (ps), default = 0
Rx.Hybrid.phiI01deg = 0;                                                   % d.c. phase shift in I branch of pol. 1 (degrees), default = 0
Rx.Hybrid.phiQ01deg = 0;                                                    % d.c. phase shift in Q branch of pol. 1 (degrees), default = 0
Rx.Hybrid.phiI02deg = 0;                                                   % d.c. phase shift in I branch of pol. 2 (degrees), default = 0
Rx.Hybrid.phiQ02deg = 0;                                                    % d.c. phase shift in Q branch of pol. 2 (degrees), default = 0

%% ============================= Photodiodes ==============================
% Constructor: pin(R, Id, BW (optional))
% R : responsivity in A/W
% Id : dark current in A
% BW : bandwidth, default = Inf. Frequency response is a
% first-order filter with bandwidth BW.
Rx.PD = pin(1, 10e-9);

%% ======================== Transimpedance Amplifier ======================
Rx.N0 = (30e-12)^2;                                                        % One-sided thermal noise PSD per real dimension
% Note: ADC filter includes all the frequecy responses from the receiver

%% ========================= Analog Components ============================
% Receiver filter
Analog.filt = design_filter('butter', 5, 0.7*sim.Rs/(sim.fs/2));

% Carrier Phase recovery type: either 'EPLL' or 'OPLL'
Analog.CarrierPhaseRecovery = CPR;
% CPRmethod: {'Costas': electric PLL based on Costas loop, which
% requires multiplications, 'logic': EPLL based on XOR operations}
Analog.CPRmethod = ReceiverType;    

if ideal
    componentFilter = [];
    componentN0 = 0;
else
    componentFilter = design_filter('bessel', 1, 0.7*sim.Rs/(sim.fs/2));
    componentRn = 60; % (Ohm) equivalent noise resistance obtained from 
    % Huber, A. et al (2002). Noise model of InP-InGaAs SHBTs for RF circuit design. 
    % IEEE Transactions on Microwave Theory and Techniques, 50(7), 1675�1682.
    componentN0 = 4e-21*componentRn/pi;
end

% Adder
Analog.Adder.filt = componentFilter;
Analog.Adder.N0 = componentN0;

% Mixer
Analog.Mixer.filt = componentFilter;
Analog.Mixer.N0 = componentN0;

% ABS
Analog.ABS.filt = componentFilter;
Analog.ABS.N0 = componentN0;

% Logic
Analog.Logic.Vcc = 1;
Analog.Logic.N0 = componentN0;
Analog.Logic.filt = componentFilter;

% Comparator
Analog.Comparator.Vref = 0;
Analog.Comparator.Vcc = 1;
Analog.Comparator.N0 = componentN0;
Analog.Comparator.filt = componentFilter;

% Loop filter
Analog.Kdc = 1;                                                            % DC gain
Analog.csi = 1/sqrt(2);                                                    % damping coefficient of second-order loop filter
Analog.Delay = Delayps;                                                         % Delay in number of samples i.e. 1/sim.fs seconds. Minimum is 1

Rx.Analog = Analog;

Tx.PlaunchdBm = -35:0.5:-20;
sim.Nsetup = sim.Ndiscard; % Number of symbols after which BER will be meaured (only for DPSK)

%% Runs simulation
switch upper(Analog.CarrierPhaseRecovery)
    case 'EPLL'
        BER = ber_coherent_analog_epll(Tx, Fiber, Rx, sim);
    case 'OPLL'
        error('OPLL not implemented yet')
    otherwise
        error('Invalid carrier phase recovery method')
end
        
if sim.save   
    % delete large variables
    clear t f Mod omega Fiber c
    sim = rmfield(sim, 'f');
    sim = rmfield(sim, 't');
    Tx.Mod = rmfield(Tx.Mod, 'Hel');
    if isfield(Tx.Mod, 'a')
        Tx.Mod = rmfield(Tx.Mod, 'a');
    end
    
    save(filename)
end