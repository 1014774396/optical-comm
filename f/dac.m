function [xa, xqzoh] = dac(x, DAC, sim)
%% Digital-to-analog conversion: quantize, sample and hold, and filter signal
% Inputs:
% - x : input signal already at the DAC sampling rate
% - DAC : DAC parameters. {resolution: effective DAC resolution, 
% rclip: clipping ratio. Clipping ratio is defined as the percentage of the
% signal amplitude that is clipped in both extremes (see code),
% ros: oversampling ratio of DAC
% filt: DAC filter after sample and hold}. 
% - sim : simulation parameters {sim.f, sim.fs, sim.Mct}
% Outputs:
% - y : output signal

% Quantize
if isfield(sim, 'quantiz') && sim.quantiz && ~isinf(DAC.resolution)
    enob = DAC.resolution;
    rclip = DAC.rclip;
    
    xmax = max(x);
    xmin = min(x);
    xamp = xmax - xmin;    
    
    % Clipping
    % clipped: [xmin, xmin + xamp*rclip) and (xmax - xamp*rclip, xmax]
    % not clipped: [xmin + xamp*rclip, xmax - xamp*rclip]
    xmin = xmin + xamp*rclip; % discounts portion to be clipped
    xmax = xmax - xamp*rclip;
    xamp = xmax - xmin;
    
    dx = xamp/(2^(enob)-1);
    
    codebook = xmin:dx:xmax;
    partition = codebook(1:end-1) + dx/2;
    [~, xq, varQ] = quantiz(x, partition, codebook); 
else
    xq = x;
    varQ = 0;
end

% Zero-order holder
Nhold = sim.Mct/DAC.ros;
assert(floor(Nhold) == ceil(Nhold), 'dac: oversampling ratio of DAC (DAC.ros) must be an integer multiple of oversampling ratio of continuous time (sim.Mct)');
% xqzoh = upfirdn(xq, ones(1, Nhold), Nhold); 
xqzoh = upsample(xq, Nhold);
xqzoh = filter(ones(1, Nhold), 1, xqzoh);

% Filter
% Filter by lowpass filter (antialiasing filter)
Hdac = ifftshift(DAC.filt.H(sim.f/sim.fs)); % rx filter frequency response

% Filtering
xa = real(ifft(fft(xqzoh).*Hdac)); % filter   
                                
% Plot
if sim.shouldPlot('Eye diagram of DAC output')  
    Ntraces = 100;
    Nstart = sim.Ndiscard*sim.Mct+1;
    Nend = min(Nstart + Ntraces*2*sim.Mct, length(xa));
    figure(301)
    subplot(211), box on
    eyediagram(xqzoh(Nstart:Nend), 2*sim.Mct)
    title('Eye diagram after ZOH')
    subplot(212), box on
    eyediagram(xa(Nstart:Nend), 2*sim.Mct)
%     eyediagram(xa(Nstart:Nend), 2*sim.Mct, sim.Mct, ceil(sim.Mct/2))
    title('Eye diagram of DAC output')
    drawnow
end