%% Calculate BER of amplified IM-DD system through montecarlo simulation
function ber = soa_ber_montecarlo(mpam, tx, soa, rx, sim)

% Random sequence
dataTX = randi([0 mpam.M-1], 1, sim.Nsymb);

% Modulated PAM signal in discrete-time
Pd = mpam.a(gray2bin(dataTX, 'pam', mpam.M) + 1);

% Add pulse 
Pt = reshape(kron(Pd, mpam.pshape).', sim.N, 1);

% Rescale to desired power
Pmin = 2/(10^(abs(tx.rex)/10)-1); % normalized minimum power when signal has unit average power
Plevels = (mpam.a/mean(Pt) + Pmin)*soa.Gain*tx.Ptx/(1 + Pmin); % levels at the receiver
Pthresh = (mpam.b/mean(Pt) + Pmin)*soa.Gain*tx.Ptx/(1 + Pmin); % decision thresholds at the receiver
Pt = (Pt/mean(Pt) + Pmin)*tx.Ptx/(1 + Pmin); % after rescaling E(Pt) = tx.Ptx

% Calculate electric field (no chirp) before amplifier
x = sqrt(Pt);

% Amplifier
et = soa.amp(x, sim.fs);
Ef = fftshift(fft(et));

% Optical bandpass filter
eo = ifft(fft(et).*ifftshift(rx.optfilt.H(f)));

% Direct detection and add thermal noise
yt = abs(eo).^2 + sqrt(rx.N0*sim.fs/2)*randn(size(eo));

% Electric low-pass filter
yt = real(ifft(fft(yt).*ifftshift(rx.elefilt.H(f))));

% Sample
yd = yt(sim.Mct/2:sim.Mct:end);

% Heuristic pdf for each level
if sim.verbose
    figure
    [nn, xx] = hist(yd(dataTX == 3), 50);
    nn = nn/trapz(xx, nn);
    bar(xx, nn)
end

% Discard first and last sim.Ndiscard symbols
ndiscard = [1:sim.Ndiscard sim.Nsymb-sim.Ndiscard+1:sim.Nsymb];
yd(ndiscard) = []; 
Pd(ndiscard) = []; 
dataTX(ndiscard) = [];

% Demodulate
dataRX = sum(bsxfun(@ge, yd, Pthresh.'), 2);
dataRX = bin2gray(dataRX, 'pam', mpam.M).';

% True BER
[~, ber] = biterr(dataRX, dataTX);