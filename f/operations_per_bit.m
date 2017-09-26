function [OPbit, Fs] = operations_per_bit(Rb, Fiber, wavelength)
%% Compute the number of operations per bit for different transmission techniques

N = 2^14;
ros = 5/4;
Mct = 5;
alpha = 0;
Efraction = 0.9;
Offt = @(Nfft) 4*Nfft.*log2(Nfft); % number of real operations assuming split-radix FFT
NtdfirReal = @(Ntaps, Nblock) Ntaps.*Nblock + Nblock.*(Ntaps-1);
NtdfirComplex = @(Ntaps, Nblock) (4*Ntaps.*Nblock + 2*Ntaps.*Nblock) + (2*Nblock.*(Ntaps-1));
NtrComplex = @(Btr) (28*Btr+1) + (7*Btr+1);
NtrReal = @(Btr) round(NtrComplex(Btr)/2);

%% 4-PAM
% Frequency domain equalizer. Nfft is chosen to minimize complexity for a
% given channel memory length
MPAM = PAM(4, Rb);
Fs.PAM4 = MPAM.Rs*ros;

[hfir, Nfir] = fir_approx(@(f) Fiber.Himdd(f, wavelength, alpha, 'small signal'), Fs.PAM4, Efraction, N, Mct);
Nfir

% Find best FFT size for filter
Nfft = 2.^(max(6, nextpow2(Nfir)):15);
N4PAMbit = (MPAM.Rs*ros)/Rb*Nops_freq_domain_equalizer(Nfft, Nfir-1, 'split radix');
[N4PAMbitFD, idx] = min(N4PAMbit);
Nfft = Nfft(idx)

% Time-domain implementation
Ntaps = Nfir;
N4PAMbitTD = (MPAM.Rs*ros)/Rb*(NtdfirReal(Ntaps, Ntaps)/Ntaps + NtrReal(Ntaps)/Ntaps);

OPbit.N4PAMbitFD = N4PAMbitFD;
OPbit.N4PAMbitTD = N4PAMbitTD;

%% 16-QAM DC-OFDM
% Number operations includes IFFT at the transmitter, FFT at the receiver,
% and single-tap frequency-domain equalizer at receiver
OFDM = ofdm(Nfft, round(Nfft/1.23), 16, Rb, 'DC');
OFDM.set_cyclic_prefix(ceil(Nfir/2), ceil(Nfir/2));
Fs.DCOFDM = OFDM.fs;

Tofdm = (OFDM.Nc + OFDM.Npos + OFDM.Nneg)/OFDM.fs;
NOFDMbit = (2*Offt(OFDM.Nc) + OFDM.Nc)/(Tofdm*Rb);

OPbit.NOFDMbit = NOFDMbit;

%% 16-QAM SSB-OFDM
% Number operations includes IFFT at the transmitter, FFT at the receiver,
% and single-tap frequency-domain equalizer at receiver
OFDM = ofdm(Nfft, round(Nfft/1.23), 16, Rb, 'SSB');
OFDM.set_cyclic_prefix(ceil(Nfir/2), ceil(Nfir/2));
Fs.SSBOFDM = OFDM.fs;

Tofdm = (OFDM.Nc + OFDM.Npos + OFDM.Nneg)/OFDM.fs;
SSBIC = NtdfirReal(14, Nfft);
NSSBOFDMbit = (2*Offt(OFDM.Nc) + OFDM.Nc + SSBIC)/(Tofdm*Rb);

OPbit.NSSBOFDMbit = NSSBOFDMbit;

%% 4-PAM KK receiver
MPAM = PAM(4, Rb);
Fs.KKPAM4 = MPAM.Rs*ros;
f = freq_time(N, 5*Fs.KKPAM4);
Gch = Fiber.Hdisp(f, wavelength);
Gch(f == 0) = 2;
Gch(f < 0) = conj(Gch(f < 0));

[hfir, Nfir] = fir_approx(@(f2) spline(f, Gch, f2), Fs.KKPAM4, Efraction, N, Mct);
Nfir

NfftUP = 1024;
Nfft = 256;
Nhilbert = 51;
NKK4PAMbit = (MPAM.Rs*ros)/Rb*(2*Offt(NfftUP) + 10*NfftUP)/(NfftUP - Nhilbert) + (MPAM.Rs*ros)/Rb*(NtdfirComplex(Nfir, Nfft) + NtrComplex(Nfft))/Nfft;

OPbit.NKK4PAMbit = NKK4PAMbit;

%% 2-D 4-PAM Stokes vector receiver
MPAM = PAM(4, Rb/2);
Fs.Stokes2D = MPAM.Rs*ros;
[hfir, Ntaps] = fir_approx(@(f) Fiber.Himdd(f, wavelength, alpha, 'small signal'), Fs.Stokes2D, Efraction, N, Mct);
Ntaps

N2DStokesbit = (MPAM.Rs*ros)/Rb*((4*NtdfirReal(Ntaps, Ntaps) + 8*Ntaps + 2*NtrReal(Ntaps))/Ntaps);

OPbit.N2DStokesbit = N2DStokesbit;

%% 3-D 4-PAM Stokes vector receiver
MPAM = PAM(4, Rb/3);
Fs.Stokes3D = MPAM.Rs*ros;
[hfir, Ntaps] = fir_approx(@(f) Fiber.Himdd(f, wavelength, alpha, 'small signal'), Fs.Stokes3D, Efraction, N, Mct);
Ntaps

N3DStokesbit = (MPAM.Rs*ros)/Rb*(4*NtdfirReal(Ntaps, Ntaps) + 3*NtdfirReal(Ntaps, Ntaps) + 20*Ntaps + 3*NtrReal(Ntaps))/Ntaps;

OPbit.N3DStokesbit = N3DStokesbit;

%% QPSK DSP-based coherent
MQAM = QAM(4, Rb/2);
[Ncd, Npmd] = Fiber.Ntaps(MQAM.Rs, ros, wavelength);
Ncd = ceil(Ncd);
Npmd = ceil(Npmd); 
n = nextpow2(Ncd);
Nfft = 2.^(max(log2(128), n):15);
Nqpsk = @(Nfft) (2*Offt(Nfft) + Nfft)./(Nfft-Ncd);
[~, idx] = min(Nqpsk(Nfft));
Nfft = Nfft(idx);

% CD (two frequency-domain equalizers)
% NopCD = 2*(2*Offt(Nfft) + Nfft);
Nblock = 128;
NopCD = 2*(NtdfirComplex(Ncd, Nblock));

% PMD 
Bpmd = Nblock;
Npmd = 3;
NopPMD = 4*(NtdfirComplex(Ncd, Nblock)) + 8;

% CR
Nf = 16;
Bcr = Nblock;
NopCR = 30.3*Bcr + 14*Nf - 4 - 4*Bcr/Nf  + 7*Bcr+6*Nf;

Fs.QPSK = MQAM.Rs*ros;
NQPSKbit = (MQAM.Rs*ros)/Rb*(NopCD + NopPMD + NopCR + 2*NtrComplex(Nblock))/(Nblock-Ncd);

OPbit.NQPSKbit = NQPSKbit;

%% 16-QAM DSP-based coherent
MQAM = QAM(16, Rb/2);
[Ncd, Npmd] = Fiber.Ntaps(MQAM.Rs, ros, wavelength);
Ncd = ceil(Ncd);
Npmd = ceil(Npmd); 
n = nextpow2(Ncd);
Nfft = 2.^(max(log2(128), n):15);
Nqpsk = @(Nfft) (2*Offt(Nfft) + Nfft)./(Nfft-Ncd);
[~, idx] = min(Nqpsk(Nfft));
Nfft = Nfft(idx);

% CD (two frequency-domain equalizers)
% NopCD = 2*(2*Offt(Nfft) + Nfft);
Nblock = 128;
NopCD = 2*(NtdfirComplex(Ncd, Nblock));

% PMD 
Bpmd = Nblock;
Npmd = 3;
NopPMD = 4*(NtdfirComplex(Ncd, Nblock)) + 8;

% CR
Nf = 16;
Bcr = Nblock;
NopCR = 30.3*Bcr + 14*Nf - 4 - 4*Bcr/Nf  + 7*Bcr+6*Nf;
  
Fs.QAM16 = MQAM.Rs*ros;
N16QAMbit = (MQAM.Rs*ros)/Rb*(NopCD + NopPMD + NopCR + 2*NtrComplex(Nblock))/(Nblock-Ncd);

OPbit.N16QAMbit = N16QAMbit;
