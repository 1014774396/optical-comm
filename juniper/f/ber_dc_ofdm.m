function [bercount, berawgn, SNRdB] = ber_dc_ofdm(ofdm, Tx, Fibers, Amp, Rx, sim)     
%% Calculate BER of pre-amplified IM-DD system through montecarlo simulation
% Inputs:
% - ofdm: OFDM class
% - Tx: struct with transmitter paramters
% - Fibers: array of Fiber classes containing the fibers used in
% transmittion i.e., Fibers = [SMF DCF] or Fibers = [SMF];
% - Amp: pre-amplifier using SOA class
% - Rx: struct with receiver parameters
% - sim: struct with simulation parameters  

%% Generate OFDM signal
[xd, Rx.AdEq.trainSeq] = ofdm.signal(sim.Nsymb); 

%% DAC
xt = dac(xd, Tx.DAC, sim);
% Note: Driving signal xd must be normalized by Vpi

% Discard first and last symbols
xt(1:sim.Mct*sim.Ndiscard) = 0; % zero sim.Ndiscard first symbols
xt(end-sim.Mct*sim.Ndiscard+1:end) = 0; % zero sim.Ndiscard last symbbols

%% Driver
xt = xt/max(abs(xt));
xt = Tx.Mod.Vswing*xt + Tx.Mod.Vbias; 

%% Generate optical signal
Tx.Laser.PdBm = Watt2dBm(Tx.Ptx);
Ecw = Tx.Laser.cw(sim);
Etx = mzm(Ecw, xt, Tx.Mod);

% Chirp
% Adds transient chirp just to measure its effect. MZM in push pull should
% have no chirp
if isfield(Tx, 'alpha') && Tx.alpha ~= 0
    disp('chirp added!')
    Etx = Etx.*exp(1j*Tx.alpha/2*log(abs(Etx).^2));
end

% Adjust power to make sure desired power is transmitted
Etx = Etx*sqrt(Tx.Ptx/mean(abs(Etx).^2));

%% Fiber propagation
Erx = Etx;
link_gain = Amp.Gain*Rx.PD.R;
for k = 1:length(Fibers)
    fiberk = Fibers(k); 
    
    Erx = fiberk.linear_propagation(Erx, sim.f, Tx.Laser.wavelength); % propagation through kth fiber in Fibers
    
    link_gain = link_gain*fiberk.link_attenuation(Tx.Laser.wavelength);
end

%% Pre-amplifier
Erx = Amp.amp(Erx, sim.fs);

%% Optical bandpass filter
Hopt = ifftshift(Rx.optfilt.H(sim.f/sim.fs));
Erx = [ifft(fft(Erx(1, :)).*Hopt);...
    ifft(fft(Erx(2, :)).*Hopt)];

%% Direct detection and add thermal noise
% PD.detect(Ein: Input electric field, fs: sampling rate of samples in Ein,
% noise statistics {'gaussian', 'no noise'}, N0: one-sided PSD of thermal
% noise)
yt = Rx.PD.detect(Erx, sim.fs, 'gaussian', Rx.N0);
yref = yt;

%% Automatic gain control
yt = yt - mean(yt);
yt = yt/mean(abs(yt).^2);

%% ADC
% ADC performs filtering, quantization, and downsampling
% For an ideal ADC, ADC.ENOB = Inf
[yk, ~, ytf] = adc(yt, Rx.ADC, sim);

%% OFDM detection
Xn = ofdm.detect(yk, Rx.AdEq, sim.shouldPlot('Adaptation MSE') || sim.shouldPlot('Constellations') || sim.shouldPlot('Equalizer'));

%% Calculate BER
[bercount, ~] = ofdm.countBER([Rx.AdEq.Ntrain+sim.Ndiscard sim.Ndiscard]);

%% AWGN approximation
[berawgn, SNRdB] =  ofdm.estimate_ber(yref, sim.Hch, sim.varNoise, sim.shouldPlot('Estimated SNR'));

%% Plots
if sim.shouldPlot('Transmitted signal spectrum')
%     Nstop = min(512*sim.Mct*(ofdm.Nc + ofdm.Npre_os), sim.N);
%     plot(sim.f/1e9, abs(fftshift(fft(xt(1:Nstop).^2)-mean(xt)).^2))
%     xlabel('Frequency (GHz)')
%     ylabel('X(f)')
%     a = axis;
%     axis([-ofdm.fs/1e9 ofdm.fs a(3:4)])
end
    