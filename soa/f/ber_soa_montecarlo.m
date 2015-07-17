%% Calculate BER of amplified IM-DD system through montecarlo simulation
function ber = ber_soa_montecarlo(mpam, tx, fiber, soa, rx, sim)

% Normalized frequency
f = sim.f/sim.fs;

% Overall link gain
link_gain = soa.Gain*fiber.link_attenuation(tx.lamb)*rx.R;

% Ajust levels to desired transmitted power and extinction ratio
mpam.adjust_levels(tx.Ptx, tx.rexdB);

% Modulated PAM signal
dataTX = randi([0 mpam.M-1], 1, sim.Nsymb); % Random sequence
xt = mpam.mod(dataTX, sim.Mct);
xt(1:sim.Mct*sim.Ndiscard) = 0; % zero sim.Ndiscard first symbols
xt(end-sim.Mct*sim.Ndiscard+1:end) = 0; % zero sim.Ndiscard last symbbols

% Generate optical signal
[Et, ~] = optical_modulator(xt, tx, sim);

% Fiber propagation
Et = fiber.linear_propagation(Et, sim.f, tx.lamb);

% Amplifier
et = soa.amp(Et, sim.fs);

% Optical bandpass filter
eo = ifft(fft(et).*ifftshift(rx.optfilt.H(f)));

%% Direct detection and add thermal noise
%% Shot noise
if isfield(sim, 'shot') && sim.shot
    q = 1.60217657e-19;      % electron charge (C)

    % Instataneous received power considering only attenuation from the fiber   
    Sshot = 2*q*(rx.R*abs(eo).^2 + rx.Id);     % one-sided shot noise PSD

    % Frequency is divided by two because PSD is one-sided
    wshot = sqrt(Sshot*sim.fs/2).*randn(size(eo));
else 
    wshot = 0;
end

% Direct detection and add noises
yt = abs(eo).^2;
yt = yt + wshot + sqrt(rx.N0*sim.fs/2)*randn(size(eo));

% Electric low-pass filter
yt = real(ifft(fft(yt).*ifftshift(rx.elefilt.H(f))));

% Sample
ix = (sim.Mct-1)/2+1:sim.Mct:length(yt); % sampling points
yd = yt(ix);

% Discard first and last sim.Ndiscard symbols
ndiscard = [1:sim.Ndiscard sim.Nsymb-sim.Ndiscard+1:sim.Nsymb];
yd(ndiscard) = []; 
dataTX(ndiscard) = [];

% Automatic gain control
yd = yd/link_gain; % just refer power values back to transmitter

% Demodulate
dataRX = mpam.demod(yd);

% True BER
[~, ber] = biterr(dataRX, dataTX);

if sim.verbose   
    % Signal
    figure(102), hold on
    plot(link_gain*Pt)
    plot(yt, '-k')
    plot(ix, yd, 'o')
    legend('Transmitted power', 'Received signal', 'Samples')
    
    % Heuristic pdf for a level
    figure(100)
    [nn, xx] = hist(yd(dataTX == 2), 50);
    nn = nn/trapz(xx, nn);
    bar(xx, nn)
    
end
