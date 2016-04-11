function [ber, SNRdB_theory] = ber_coherent_with_matched_filtering(Tx, Fiber, Rx, sim)
%% Simulate transmission of coherent system. The receiver consists of 
%% matched filter matched to the channel impulse response, symbol-rate sampling
%% and linear equalization
dataTX = randi([0 sim.M-1], [2, sim.Nsymb]); % symbol stream for each polarization

[Vin, symbolsTX] = QAM_SC_Tx(dataTX, Tx, sim); % generates QAM signal

% Modulation format
M = sim.M; % Modulation order
if strcmpi(sim.ModFormat, 'QAM')
    demodulate = @(X) qamdemod(X, M, 0, 'gray');
elseif strcmpi(sim.ModFormat, 'DPSK')
    demodulate = @(X) dpskdemod(1/sqrt(2)*exp(-1j*pi/4)*X, M, 0, 'gray').';
    % 1/sqrt(2)*exp(-1j*pi/4) is to generate same constellation as if using 4-QAM
else
    error('ber_coherent/invalid modulation format');
end

% BER in AWGN channel
berAWGN = @(SNRdB) berawgn(SNRdB - 10*log10(log2(M)), lower(sim.ModFormat), M);

% Transmitted power swipe
ber.count = zeros(size(Tx.PlaunchdBm));
ber.theory = zeros(size(Tx.PlaunchdBm));
for k = 1:length(Tx.PlaunchdBm)
    validInd = 1:sim.Nsymb;
    
    Tx.Laser.PdBm = Tx.PlaunchdBm(k);
    
    Ein = Tx.Laser.cw(sim); % Generates electric field with intensity and phase noise
    
    if strcmpi(sim.Modulator, 'MZM')
        Ein = mzm(Ein, Vin, Tx.Mod); % modulate optical signal using eletro-optical modulator (EOM)
    else
        Ein = SiPh_optical_mod(Ein, Vin, Tx.Mod);
    end
    
    % Makes sure that transmitted power is a desired level
    Ein = Ein*sqrt(dBm2Watt(Tx.PlaunchdBm(k))/sum(mean(abs(Ein).^2, 2)));

    %% ========= Propagation ========== 
    Erec = Fiber.linear_propagation(Ein, sim.f, Tx.Laser.lambda);

    %% ========= Receiver =============
    [Y, ~] = PDM_QAM_Rx(Erec, sim.M, Rx, sim);
        
    %% Matched filtering and equalization
    eq.type = 'fixed td-sr-le';
    eq.Ntaps = 11;
    mpam = PAM(2, sim.Rs, 'equally-spaced', @(n) double(n >= 0 & n < sim.Mct));
    Hch = (Tx.filt.H(sim.f/sim.fs).*Tx.Mod.Hel).';
    sim.f = sim.f.';
    [Ydxi, eq] = equalize(eq, real(Y(1, :).'), Hch, mpam, Rx, sim);
    [Ydxq, eq] = equalize(eq, imag(Y(1, :).'), Hch, mpam, Rx, sim);
    [Ydyi, eq] = equalize(eq, real(Y(2, :).'), Hch, mpam, Rx, sim);
    [Ydyq, eq] = equalize(eq, imag(Y(2, :).'), Hch, mpam, Rx, sim);    
    
    Yd = [Ydxi + 1j*Ydxq, Ydyi + 1j*Ydyq];
    
    sim.f = sim.f.';
    Yd = Yd.';
   
    % Estimate SNR including noise enhacement penalty
    Prx = dBm2Watt(Tx.Laser.PdBm)/Fiber.link_attenuation(Tx.Laser.lambda);
    Plo = dBm2Watt(Rx.LO.PdBm);
    noiseBW = trapz(sim.f, abs(eq.Hrx.'.*eq.Hff(sim.f/sim.Rs)).^2)/2

    Ppd = abs(sqrt(Plo/(4*sim.Npol)) + sqrt(Prx/(4*sim.Npol))).^2; % incident power in each photodiode
    Psig = 1/sqrt(2)*Plo*Prx/(sim.Npol*sim.Npol); % Signal power per real dimension
    varShot = 2*Rx.PD.varShot(Ppd, noiseBW); % Shot noise variance per real dimension
    varThermal = Rx.N0*noiseBW; % Thermal noise variance per real dimension
    SNRdB_theory(k) = 10*log10(Psig/(varShot + varThermal));
       
    % Demodulate
    dataRX = [demodulate(Yd(1, :)); demodulate(Yd(2, :))];
    dataRX(:, [1:sim.Ndiscard end-sim.Ndiscard+1:end]) = []; % discard first and last sim.Ndiscard symbols
    validInd([1:sim.Ndiscard end-sim.Ndiscard+1:end]) = []; 
    
    % BER calculation
%     figure, stem(dataTX(1, validInd) ~= dataRX(1, :))
%     drawnow
    [~, berX(k)] = biterr(dataTX(1, validInd), dataRX(1, :))
    [~, berY(k)] = biterr(dataTX(2, validInd), dataRX(2, :))
    ber.count(k) = 0.5*(berX(k) + berY(k));
    ber.theory(k) = berAWGN(SNRdB_theory(k))
end

plots

if isfield(sim, 'Plots') && sim.Plots('BER') && length(ber.count) > 1
    figure(100), box on, hold on
    [~, link_attdB] = Fiber.link_attenuation(Tx.Laser.lambda);
    Prx = Tx.PlaunchdBm - link_attdB;
    plot(Prx, log10(ber.theory), '-')
    plot(Prx, log10(ber.count), '-o')
    legend('Theory including noise enhancement', 'Counted')
    xlabel('Received Power (dBm)')
    ylabel('log_{10}(BER)')
    axis([Prx(1) Prx(end) -8 0])
end
    
