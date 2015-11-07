function margin_vs_gain_qsub(M, ka, level_spacing, BW0GHz, GainBWGHz, modBWGHz)
%% Function to calculate power margin vs gain in bactch simulation on corn
% On server inputs are passed as strings
% - M = PAM order
% - ka = impact ionization factor
% - level_spacing = {eqully-spaced, optimized}
% - BW0GHz = low-gain APD bandwidth in GHz
% - GainBWGHz = Gain-bandwidth product in GHz
% - modBW = modulator BW in GHz
% Note: BW0GHz = Inf and GainBWGHz = Inf and modBW = Inf, this corresponds
% to AWGN simulation

% add subdirectories
addpath ../mpam
addpath ../f
addpath f

% Convert inputs to double
if ~isnumeric([M, ka, BW0GHz, GainBWGHz, modBWGHz])
    M = str2double(M);
    ka = str2double(ka);
    BW0GHz = str2double(BW0GHz);
    GainBWGHz = str2double(GainBWGHz);
    modBWGHz = str2double(modBWGHz);
end

% Simulation parameters
sim.Nsymb = 2^20; % Number of symbols in montecarlo simulation
sim.Mct = 9;    % Oversampling ratio to simulate continuous time (must be odd so that sampling is done  right, and FIR filters have interger grpdelay)  
sim.L = 2;      % de Bruijin sub-sequence length (ISI symbol length)
sim.BERtarget = 1.8e-4; 
sim.Ndiscard = 16; % number of symbols to be discarded from the begning and end of the sequence
sim.N = sim.Mct*sim.Nsymb; % number points in 'continuous-time' simulation

%
sim.shot = true; % include shot noise (apd simulations always include shot noise)
sim.RIN = true; % include RIN noise. Only included in montecarlo simulation
sim.verbose = false; % show stuff

% M-PAM
mpam = PAM(M, 100e9, level_spacing, @(n) double(n >= 0 & n < sim.Mct)); 

%% Time and frequency
sim.fs = mpam.Rs*sim.Mct;  % sampling frequency in 'continuous-time'

dt = 1/sim.fs;
t = (0:dt:(sim.N-1)*dt).';
df = 1/(dt*sim.N);
f = (-sim.fs/2:df:sim.fs/2-df).';

sim.t = t;
sim.f = f;

%% Transmitter
tx.lamb = 1310e-9; % wavelength
tx.alpha = 0; % chirp parameter
tx.RIN = -150;  % dB/Hz
tx.rexdB = -10;  % extinction ratio in dB. Defined as Pmin/Pmax

if mpam.M == 4
    tx.PtxdBm = -22:1:-6; % range for equally spaced levels
elseif mpam.M == 8
    tx.PtxdBm = -18:1:-5; % range for equally spaced levels
end

% Modulator frequency response
if ~isinf(modBWGHz)
    disp('> Modulator included')
    tx.modulator.fc = 1e9*modBWGHz; % modulator cut off frequency
    tx.modulator.H = @(f) 1./(1 + 2*1j*f/tx.modulator.fc - (f/tx.modulator.fc).^2);  % laser freq. resp. (unitless) f is frequency vector (Hz)
    tx.modulator.h = @(t) (2*pi*tx.modulator.fc)^2*t(t >= 0).*exp(-2*pi*tx.modulator.fc*t(t >= 0));
    tx.modulator.grpdelay = 2/(2*pi*tx.modulator.fc);  % group delay of second-order filter in seconds
end

%% b2b
b2b = fiber();

%% Receiver
rx.N0 = (30e-12).^2; % thermal noise psd
rx.Id = 10e-9;
rx.R = 1;

%% PIN
% (GaindB, ka, BW, R, Id) 
pin = apd(0, 0, Inf, rx.R, rx.Id);
   
%% APD 
% (GaindB, ka, BW, R, Id) 
apdG = apd(10, ka, 1e9*[BW0GHz GainBWGHz], rx.R, rx.Id);

%% Equalization
if isinf(apdG.BW) && isinf(modBWGHz) % awgn simulation
    disp('> Equalizer = None')
    rx.eq.type = 'None';
    rx.elefilt = design_filter('matched', mpam.pshape, 1/sim.Mct);
else
    disp('> Equalizer = fixed time-domain symbol-rate linear equalizer')
    rx.eq.type = 'Fixed TD-SR-LE';
    rx.eq.Ntaps = 31;
end

%% Calculate BER for PIN with same properties, but inifinite bandwidth
ber_pin = apd_ber(mpam, tx, b2b, pin, rx, sim);

PtxdBm_pin_BERtarget = interp1(log10(ber_pin.gauss), tx.PtxdBm, log10(sim.BERtarget));

% Variable to iterate
Gains = 1:2:20;

% APD
PtxdBm_BERtarget = zeros(size(Gains));

% figure, hold on, box on
% leg = {};
% hline(1) = plot(tx.PtxdBm, log10(ber_pin.gauss), '-b');
% plot(tx.PtxdBm, log10(ber_pin.awgn), '--', 'Color', get(hline(1), 'Color'))
% plot(tx.PtxdBm, log10(ber_pin.count), '-o', 'Color', get(hline(1), 'Color'))
% leg = [leg 'PIN'];
for k= 1:length(Gains)
    fprintf('- %d-PAM, %s, ka = %.2f, BW0 = %.2f, GainBW = %.2f, Gain = %.2f\n',...
        mpam.M, mpam.level_spacing, ka, apdG.BW0/1e9, apdG.GainBW/1e9, Gains(k))

    apdG.Gain = Gains(k);

    % BER
    ber_apd = apd_ber(mpam, tx, b2b, apdG, rx, sim);
    BER(k) = ber_apd;

    % Calculate power at the target BER
    PtxdBm_BERtarget(k) = interp1(log10(ber_apd.gauss), tx.PtxdBm, log10(sim.BERtarget));

    % Figures
%     hline(k+1) = plot(tx.PtxdBm, log10(ber_apd.gauss), '-');
%     plot(tx.PtxdBm, log10(ber_apd.awgn), '--', 'Color', get(hline(k+1), 'Color'))
%     plot(tx.PtxdBm, log10(ber_apd.count), '-o', 'Color', get(hline(k+1), 'Color'))
%     leg = [leg sprintf('Gain = %.2f', apdG.Gain)];
end   
% xlabel('Received Power (dBm)')
% ylabel('log(BER)') 
% axis([tx.PtxdBm(1) tx.PtxdBm(end) -8 0])
% set(gca, 'xtick', tx.PtxdBm)
% title(sprintf('%d-PAM, %s, ka = %.2f, BW0 = %.2f, GainBW', mpam.M, mpam.level_spacing, ka, BW0GHz, GainBWGHz))

% Calculate margin   
MargindB = PtxdBm_pin_BERtarget - PtxdBm_BERtarget;

% Find gain for optimal margin
sim.OptimizeGain = true;

% Optimal gain
[ber_apd_opt, ~, apdG] = apd_ber(mpam, tx, b2b, apdG, rx, sim);
Gopt_margin = apdG.Gain;

PtxdBm_BERtarget_opt = interp1(log10(ber_apd_opt.gauss), tx.PtxdBm, log10(sim.BERtarget));

OptMargindB = PtxdBm_pin_BERtarget - PtxdBm_BERtarget_opt;  

% Plot optimal gain
% hline(end+1) = plot(tx.PtxdBm, log10(ber_apd_opt.gauss), '-k');
% plot(tx.PtxdBm, log10(ber_apd_opt.awgn), '--', 'Color', get(hline(end), 'Color'))
% plot(tx.PtxdBm, log10(ber_apd_opt.count), '-o', 'Color', get(hline(end), 'Color'))
% leg = [leg sprintf('Optimal Gain = %.2f', apdG.Gain)];
% legend(hline, leg)  
% drawnow

% Save results
filename = sprintf('results/data/margin_vs_gain_%d-PAM_%s_ka=%d_BW0=%d_GainBW=%d_modBW=%d',...
    mpam.M, mpam.level_spacing, round(100*ka), BW0GHz, GainBWGHz, modBWGHz);
sim = rmfield(sim, 't');
sim = rmfield(sim, 'f');
save(filename)
