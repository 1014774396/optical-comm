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

sim.shot = false; % include shot noise in montecarlo simulation (always included for pin and apd case)
sim.RIN = false; % include RIN noise in montecarlo simulation
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
        tx.PtxdBm = -26:1:-10;
    case 8
        tx.PtxdBm = -22:2:-4;
    case 16
       tx.PtxdBm = -18:2:-2;
end
   
tx.lamb = 1310e-9; % wavelength
tx.alpha = 0; % chirp parameter
tx.RIN = -150;  % dB/Hz
tx.rexdB = -15;  % extinction ratio in dB. Defined as Pmin/Pmax

% Modulator frequency response
tx.kappa = 1; % controls attenuation of I to P convertion
% tx.modulator.fc = 30e9; % modulator cut off frequency
% tx.modulator.H = @(f) 1./(1 + 2*1j*f/tx.modulator.fc - (f/tx.modulator.fc).^2);  % laser freq. resp. (unitless) f is frequency vector (Hz)
% tx.modulator.h = @(t) (2*pi*tx.modulator.fc)^2*t(t >= 0).*exp(-2*pi*tx.modulator.fc*t(t >= 0));
% tx.modulator.grpdelay = 2/(2*pi*tx.modulator.fc);  % group delay of second-order filter in seconds

%% Fiber
fiber = fiber(); % fiber(L, att(lamb), D(lamb))

%% Receiver
rx.N0 = (20e-12).^2; % thermal noise psd
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

%% PIN
% (GaindB, ka, GainBW, R, Id) 
pin = apd(0, 0, Inf, rx.R, rx.Id);

%% APD 
% (GaindB, ka, GainBW, R, Id) 
% finite Gain x BW
apd_fin = apd(8.1956, 0.09, 340e9, rx.R, rx.Id); % gain optimized for uniformly-spaced 4-PAM with matched filter
% apd_fin = apd(7.86577063943086, 0.09, 340e9, rx.R, rx.Id); % gain optimized for uniformly-spaced 8-PAM with matched filter
% apd_fin.optimize_gain(mpam, tx, fiber, rx, sim);

if strcmp(mpam.level_spacing, 'equally-spaced')
     % uniform, infinite Gain x BW (4-PAM)
    apd_inf = apd(11.8876, 0.09, Inf, 1, 10e-9); % gain optimized for 4-PAM with matched filter
%     apd_inf.optimize_gain(mpam, tx, fiber, rx, sim);

%     apd_inf = apd(7.865770639430862, 0.09, Inf, rx.R, rx.Id); % gain optimized for 8-PAM with matched filter
elseif strcmp(mpam.level_spacing, 'optimized')
    % nonuniform, infinite gain x BW
    apd_inf = apd(13.8408, 0.09, Inf, rx.R, rx.Id); % gain optimized for 4-PAM with matched filter
%     apd_inf.optimize_gain(mpam, tx, fiber, rx, sim);
end

%% SOA
% soa(GaindB, NF, lambda, maxGaindB)
soa = soa(20, 9, 1310e-9, 20); 

% BER
disp('BER with SOA')
ber_soa = soa_ber(mpam, tx, fiber, soa, rx, sim);
disp('BER with APD with finite gain-bandwidth product')
ber_apd_fin = apd_ber(mpam, tx, fiber, apd_fin, rx, sim);
disp('BER with APD with infinite gain-bandwidth produc')
ber_apd_inf = apd_ber(mpam, tx, fiber, apd_inf, rx, sim);
disp('BER with PIN')
ber_pin = apd_ber(mpam, tx, fiber, pin, rx, sim);

%% Analysis using AWGN approximation
apd_link_gain = apd_inf.Gain*fiber.link_attenuation(tx.lamb)*rx.R;
soa_link_gain = soa.Gain*fiber.link_attenuation(tx.lamb)*rx.R;

varTherm = rx.N0*rx.elefilt.noisebw(sim.fs)/2; % variance of thermal noise

% Optimize level spacing using Gaussian approximation
Deltaf = rx.elefilt.noisebw(sim.fs)/2; % electric filter one-sided noise bandwidth
Deltafopt = rx.optfilt.noisebw(sim.fs); % optical filter two-sided noise bandwidth

soa_noise_std = @(Plevel) sqrt(varTherm + 2*Plevel*soa.N0*Deltaf + 2*soa.N0^2*Deltafopt*Deltaf*(1-1/(2*Deltafopt/Deltaf)));
% Note: Plevel corresponds to the level after SOA amplification.
% Therefore, the soa.Gain doesn't appear in the second term because
% it's already included in the value of Plevel.
% Note: second term corresponds to sig-sp beat noise, and third term
% corresponds to sp-sp beat noise with noise in one polarization.
% Change the 2 to 4 in third term to simulate noise in two pols.

apd_noise_std = @ (Plevel) sqrt(varTherm + apd_inf.var_shot(Plevel/apd_inf.Gain, rx.elefilt.noisebw(sim.fs)/2));

for k = 1:length(tx.PtxdBm)
    Ptx = 1e-3*10^(tx.PtxdBm(k)/10);
    
    % APD
    if strcmp(mpam.level_spacing, 'optimized')
        mpam.optimize_level_spacing_gauss_approx(sim.BERtarget, tx.rexdB, apd_noise_std);     
    end
    
    mpam.adjust_levels(Ptx*apd_link_gain, tx.rexdB);

    ber_apd_inf.analysis(k) = mpam.ber_awgn(apd_noise_std);
    
    % SOA
    if strcmp(mpam.level_spacing, 'optimized')
        mpam.optimize_level_spacing_gauss_approx(sim.BERtarget, tx.rexdB, soa_noise_std);     
    end
    
    mpam.adjust_levels(Ptx*soa_link_gain, tx.rexdB);

    ber_soa.analysis(k) = mpam.ber_awgn(soa_noise_std);    
    
end


%% Figures
figure, hold on, grid on, box on
plot(tx.PtxdBm, log10(ber_soa.est), '-b')
plot(tx.PtxdBm, log10(ber_soa.analysis), '-*b')

plot(tx.PtxdBm, log10(ber_apd_fin.gauss), '-r')
plot(tx.PtxdBm, log10(ber_apd_inf.gauss), '-m')
plot(tx.PtxdBm, log10(ber_apd_inf.analysis), '-*m')
plot(tx.PtxdBm, log10(ber_pin.gauss), '-k')

plot(tx.PtxdBm, log10(ber_soa.count), ':ob')
plot(tx.PtxdBm, log10(ber_apd_fin.count), ':or')
plot(tx.PtxdBm, log10(ber_apd_inf.count), ':om')
plot(tx.PtxdBm, log10(ber_pin.count), ':ok')

plot(tx.PtxdBm, log10(ber_soa.gauss), '--b')
plot(tx.PtxdBm, log10(ber_apd_fin.est), '--r')
plot(tx.PtxdBm, log10(ber_apd_inf.est), '--m')

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
    