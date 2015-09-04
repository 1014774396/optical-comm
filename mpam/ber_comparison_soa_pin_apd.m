%% Compare performance of M-PAM in 3 different scenarios
% 1. PIN receiver, no amplifier
% 2. SOA & PIN receiver
% 3. APD
clear, clc, close all

addpath ../f % general functions
addpath ../soa
addpath ../soa/f
addpath ../apd
addpath ../apd/f

%% Simulation parameters
sim.Nsymb = 2^15; % Number of symbols in montecarlo simulation
sim.Mct = 15;     % Oversampling ratio to simulate continuous time (must be odd so that sampling is done  right, and FIR filters have interger grpdelay)  
sim.L = 2;        % de Bruijin sub-sequence length (ISI symbol length)
sim.Me = 16; % number of used eigenvalues
sim.BERtarget = 1e-4; 
sim.Ndiscard = 16; % number of symbols to be discarded from the begning and end of the sequence
sim.N = sim.Mct*sim.Nsymb; % number points in 'continuous-time' simulation

sim.polarizer = false;
sim.shot = true; % include shot noise in montecarlo simulation (always included for pin and apd case)
sim.RIN = true; % include RIN noise in montecarlo simulation
sim.verbose = false; % show stuff

%% M-PAM
mpam = PAM(4, 100e9, 'equally-spaced', @(n) double(n >= 0 & n < sim.Mct));

%% Time and frequency
sim.fs = mpam.Rs*sim.Mct;  % sampling frequency in 'continuous-time'

dt = 1/sim.fs;
t = (0:dt:(sim.N-1)*dt).';
df = 1/(dt*sim.N);
f = (-sim.fs/2:df:sim.fs/2-df).';

sim.t = t;
sim.f = f;

%% Transmitter
switch mpam.M
    case 4
        tx.PtxdBm = -30:1:-12;
    case 8
        tx.PtxdBm = -22:2:-4;
    case 16
       tx.PtxdBm = -18:2:-2;
end
   
tx.lamb = 1310e-9; % wavelength
tx.alpha = 0; % chirp parameter
tx.RIN = -150;  % dB/Hz
tx.rexdB = -10;  % extinction ratio in dB. Defined as Pmin/Pmax

% Modulator frequency response
% tx.modulator.fc = 30e9; % modulator cut off frequency
% tx.modulator.H = @(f) 1./(1 + 2*1j*f/tx.modulator.fc - (f/tx.modulator.fc).^2);  % laser freq. resp. (unitless) f is frequency vector (Hz)
% tx.modulator.h = @(t) [0*t(t < 0) (2*pi*tx.modulator.fc)^2*t(t >= 0).*exp(-2*pi*tx.modulator.fc*t(t >= 0))];
% tx.modulator.grpdelay = 2/(2*pi*tx.modulator.fc);  % group delay of second-order filter in seconds

%% Fiber
fiber = fiber(); % fiber(L, att(lamb), D(lamb))

%% Receiver
rx.N0 = (30e-12).^2; % thermal noise psd
rx.Id = 10e-9; % dark current
rx.R = 1; % responsivity
% Electric Lowpass Filter
% rx.elefilt = design_filter('bessel', 5, mpam.Rs/(sim.fs/2));
rx.elefilt = design_filter('matched', mpam.pshape, 1/sim.Mct);
% rx.elefilt = design_filter('matched', @(t) conv(mpam.pshape(t), 1/sim.fs*tx.modulator.h(t/sim.fs), 'full') , 1/sim.Mct);
% Optical Bandpass Filter
rx.optfilt = design_filter('fbg', 0, 200e9/(sim.fs/2));

% KLSE Fourier Series Expansion (done here because depends only on filters
% frequency response)
% klse_fourier(rx, sim, N, Hdisp)
[rx.U_fourier, rx.D_fourier, rx.Fmax_fourier] = klse_fourier(rx, sim, sim.Mct*(mpam.M^sim.L + 2*sim.L)); 

%% Equalization
% rx.eq.type = 'Fixed TD-SR-LE';
% % rx.eq.ros = 2;
% rx.eq.Ntaps = 15;
% rx.eq.Ntrain = 2e3;
% rx.eq.mu = 1e-2;

%% PIN
% (GaindB, ka, GainBW, R, Id) 
pin = apd(0, 0, Inf, rx.R, rx.Id);

%% APD 
% (GaindB, ka, GainBW, R, Id) 
% finite Gain x BW
apd_fin = apd(8.1956, 0.09, 340e9, rx.R, rx.Id); % gain optimized for uniformly-spaced 4-PAM with matched filter
% apd_fin.optGain(this, mpam, tx, fiber, rx, sim, objective)

apd_inf = apd(11.8876, 0.09, Inf, 1, 10e-9); % gain optimized for 4-PAM with matched filter
apd_inf.Gain = apd_inf.optGain(mpam, tx, fiber, rx, sim, 'margin');

%% SOA
% soa(GaindB, NF, lambda, maxGaindB)
soa = soa(20, 7, 1310e-9, 20); 

% BER
disp('BER with SOA')
ber_soa = soa_ber(mpam, tx, fiber, soa, rx, sim);
disp('BER with APD with finite gain-bandwidth product')
ber_apd_fin = apd_ber(mpam, tx, fiber, apd_fin, rx, sim);
disp('BER with APD with infinite gain-bandwidth produc')
ber_apd_inf = apd_ber(mpam, tx, fiber, apd_inf, rx, sim);
disp('BER with PIN')
ber_pin = apd_ber(mpam, tx, fiber, pin, rx, sim);


%% Figures
figure, hold on, grid on, box on
plot(tx.PtxdBm, log10(ber_soa.est), '-b')
plot(tx.PtxdBm, log10(ber_apd_fin.gauss), '-r')
plot(tx.PtxdBm, log10(ber_apd_inf.gauss), '-m')
plot(tx.PtxdBm, log10(ber_pin.gauss), '-k')

plot(tx.PtxdBm, log10(ber_soa.count), '--ob')
plot(tx.PtxdBm, log10(ber_apd_fin.count), '--or')
plot(tx.PtxdBm, log10(ber_apd_inf.count), '--om')
plot(tx.PtxdBm, log10(ber_pin.count), '--ok')

plot(tx.PtxdBm, log10(ber_soa.gauss), '--b')

plot(tx.PtxdBm, log10(ber_soa.awgn), ':b')
plot(tx.PtxdBm, log10(ber_apd_fin.awgn), ':r')
plot(tx.PtxdBm, log10(ber_apd_inf.awgn), ':m')
plot(tx.PtxdBm, log10(ber_pin.awgn), ':k')

xlabel('Received Power (dBm)')
ylabel('log(BER)')
legend('SOA', 'APD Gain x BW = 340 GHz', 'APD Gain x BW = Inf', 'PIN', 'Location', 'SouthWest')
axis([tx.PtxdBm(1) tx.PtxdBm(end) -8 0])
set(gca, 'xtick', tx.PtxdBm)

%% Plot Frequency response
% signal = design_filter('matched', mpam.pshape, 1/sim.Mct);
% Hsig = signal.H(sim.f/sim.fs); % signal frequency response
% figure, box on, grid on, hold on
% plot(f/1e9, abs(Hsig).^2)
% if isfield(tx, 'modulator')
%     plot(f/1e9, abs(tx.modulator.H(f)).^2)
% else
%     plot(f/1e9, ones(size(f)))
% end
% plot(f/1e9, abs(fiber.Hfiber(f, tx)).^2)
% plot(f/1e9, abs(rx.optfilt.H(f/sim.fs)).^2)
% plot(f/1e9, abs(rx.elefilt.H(f/sim.fs)).^2)
% legend('Signal', 'Modulator', 'Fiber frequency response (small-signal)', 'Optical filter', 'Receiver electric filter')
% xlabel('Frequency (GHz)')
% ylabel('|H(f)|^2')
% axis([0 rx.Fmax_fourier*sim.fs/1e9 0 3])
    