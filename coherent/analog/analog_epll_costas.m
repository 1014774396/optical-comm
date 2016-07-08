function [Xs, S, Sf, Analog] = analog_epll_costas(Ys, totalLineWidth, Analog, sim)
%% Analog electric phase locked loop via Costas loop
% Inputs:
% - Ys: received signal after filtering to remove noise
% - totalLineWidth: sum of linewidths of transmitter and LO lasers
% - Analog: structure containing parameters of analog components, which
% include Mixer, Adder, Comparator
% - sim: simulation parameters {t: time, f: frequency, fs: sampling
% frequency}
% Outputs:
% - Xs: signal after four quadrant multiplier. Group delay is removed so
% sampling can be done without any offset
% - S: loop filter input
% - Sf: loop filter output
% - Analog: loop filter parameters

% Create components
% Mixers and adders for four quadrant multiplier for X and Y
Mx1 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
Mx2 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
Mx3 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
Mx4 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
Sx1 = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);
Sx2 = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);

My1 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
My2 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
My3 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
My4 = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
Sy1 = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);
Sy2 = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);

% Comparators
Comp1 = AnalogComparator(Analog.Comparator.filt, Analog.Comparator.N0, sim.fs, Analog.Comparator.Vcc);
Comp2 = AnalogComparator(Analog.Comparator.filt, Analog.Comparator.N0, sim.fs, Analog.Comparator.Vcc);
Comp3 = AnalogComparator(Analog.Comparator.filt, Analog.Comparator.N0, sim.fs, Analog.Comparator.Vcc);
Comp4 = AnalogComparator(Analog.Comparator.filt, Analog.Comparator.N0, sim.fs, Analog.Comparator.Vcc);

MixerIdQx = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
MixerQdIx = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
MixerIdQy = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);
MixerQdIy = AnalogMixer(Analog.Mixer.filt, Analog.Mixer.N0, sim.fs);

AdderX = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);
AdderY = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);
AdderXY = AnalogAdder(Analog.Adder.filt, Analog.Adder.N0, sim.fs);

% Converts delay to number of samples in order to avoid interpolation
Delay = round(Analog.Delay*sim.fs) + 1; % delay is at least one sample

% Calculate group delay
totalGroupDelay = Mx1.groupDelay + Sx1.groupDelay... % Four quadrant multiplier
    + Comp1.groupDelay + MixerIdQx.groupDelay + AdderX.groupDelay + AdderXY.groupDelay... % phase estimation    
    + Delay/sim.fs; % Additional loop delay e.g., propagation delay (minimum is 1/sim.fs since simulation is done in discrete time)
fprintf('Total loop delay: %.3f ps (%.2f bits, %d samples)\n', totalGroupDelay*1e12, totalGroupDelay*sim.Rb, ceil(totalGroupDelay*sim.fs));

LoopDelaySamples = round(totalGroupDelay*sim.fs); % loop delay in samples

% Optimize EPLL parameters
Analog.wn = optimizePLL(Analog.csi, Analog.Kdc, totalGroupDelay, totalLineWidth, sim);
Analog.EPLL.nums = Analog.Kdc*[2*Analog.csi*Analog.wn Analog.wn^2];
Analog.EPLL.dens = [1 0 0]; % descending powers of s
[Analog.EPLL.numz, Analog.EPLL.denz] = impinvar(Analog.EPLL.nums, Analog.EPLL.dens, sim.fs);
fprintf('Loop filter fn: %.3f GHz\n', Analog.wn/(2*pi*1e9));

% Loop filter
LoopFilter = ClassFilter(Analog.EPLL.numz, Analog.EPLL.denz, sim.fs);

%% Loop
X = zeros(4, length(sim.t));
Xd = zeros(4, length(sim.t));
S = zeros(size(sim.t));
Sf = zeros(size(sim.t));

Yxi = real(Ys(1, :));
Yxq = imag(Ys(1, :));
Yyi = real(Ys(2, :));
Yyq = imag(Ys(2, :));

for t = LoopDelaySamples+1:length(sim.t)
    % VCO: generates VCO output
    Vcos = cos(Sf(t-LoopDelaySamples));
    Vsin = sin(Sf(t-LoopDelaySamples));

    % Downconversion             
    X(1, t) = Sx1.add(Mx1.mix(Yxi(t), Vcos), -Mx2.mix(Yxq(t), Vsin)); % pol X, I
    X(2, t) = Sx2.add(Mx3.mix(Yxi(t), Vsin), Mx4.mix(Yxq(t), Vcos)); % pol X, Q
    X(3, t) = Sy1.add(My1.mix(Yyi(t), Vcos), -My2.mix(Yyq(t), Vsin)); % pol Y, I
    X(4, t) = Sy2.add(My3.mix(Yyi(t), Vsin), My4.mix(Yyq(t), Vcos)); % pol Y, Q

    % Phase estimation
    Xd(1, t) = Comp1.compare(X(1, t), Analog.Comparator.Vref);
    Xd(2, t) = Comp2.compare(X(2, t), Analog.Comparator.Vref);
    Xd(3, t) = Comp3.compare(X(3, t), Analog.Comparator.Vref);
    Xd(4, t) = Comp4.compare(X(4, t), Analog.Comparator.Vref);

    Sx = AdderX.add(MixerIdQx.mix(Xd(1, t), X(2, t)), -MixerQdIx.mix(Xd(2, t), X(1, t)));
    Sy = AdderY.add(MixerIdQy.mix(Xd(3, t), X(4, t)), -MixerQdIy.mix(Xd(4, t), X(3, t)));
    S(t) = AdderXY.add(Sx, Sy);

    % Loop filter
    Sf(t) = LoopFilter.filter(S(t));  
end

% Build output
Xs = [X(1, :) + 1j*X(2, :); X(3, :) + 1j*X(4, :)];

% Remove delay
delay = round((Mx1.groupDelay + Sx1.groupDelay)*sim.fs); % Group delay of four quadrant multiplier
Xs = [Xs(:, delay+1:end) Xs(:, 1:delay)]; % remove group delay

% Rotate constellation by pi/4
Xs = Xs*exp(1j*pi/4);

