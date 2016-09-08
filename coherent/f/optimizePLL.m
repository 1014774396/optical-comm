function [wnOpt, wn, phiError] = optimizePLL(csi, Delay, linewidth, sim, verbose)
%% Optimizes PLL relaxation frequency given csi (damping), Delay, linewidth for a target BER

Ts = 1/sim.Rs;
M = sim.ModFormat.M;
BER = sim.BERtarget;
SNRdB = SNRreq(BER, M, sim.ModFormat.type);
SNR = 10^(SNRdB/10);
etac = mean(abs(sim.ModFormat.mod(0:M-1)).^2)/mean(1./abs(sim.ModFormat.mod(0:M-1)).^2);

varPN = 2*pi*linewidth*Ts;

wn = 1e9*(0:0.01:1);
w = linspace(-0.5/Ts, 0.5/Ts, 1e3);
GammaPN = zeros(size(wn));
GammaAWGN = zeros(size(wn));
phiError = zeros(size(wn));
for k = 1:length(wn)
    numFs = [2*csi*wn(k) wn(k)^2];
    denFs = [1 0];
    
    Fw = polyval(numFs, 1j*w)./polyval(denFs, 1j*w);
    
    % 1/(s + Fs) = denFs/(denFs*s + numFs)
%     [num1, den1] = tfdata(1/(s + Fs));
    H1 = 1j*w + exp(-1j*w*Delay).*Fw;
    GammaPN(k) = 2*csi*wn(k)/pi*trapz(w, 1./abs(H1).^2);
    
    % Fs/(s + Fs) = numFs*denFs/(denFs*s + numFs)
%     [num2, den2] = tfdata(Fs/(s + Fs));
    H2 = Fw./(1j*w + exp(-1j*w*Delay).*Fw);
    GammaAWGN(k) = 2*csi/(pi*(1 + 4*csi^2)*wn(k))*trapz(w, abs(H2).^2);
    
    phiError(k) = varPN/(2*csi*wn(k)*Ts)*GammaPN(k) + (1 + 4*csi^2)*wn(k)*Ts/(4*csi)*(etac/(2*SNR))*GammaAWGN(k);
end

[minPhiError, ind] = min(phiError);
wnOpt = wn(ind);

if exist('verbose', 'var') && verbose
    figure(300), hold on
    h = plot(wn/1e9, phiError);
    plot(wnOpt/1e9, minPhiError, 'o', 'Color', get(h, 'Color'))
    xlabel('\omega_n (Grad/s)')
    ylabel('Phase error variance (rad^2)')
end