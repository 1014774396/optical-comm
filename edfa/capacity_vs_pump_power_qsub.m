function [E, Signal, num, approx] = capacity_vs_pump_power_qsub(edf_type, pumpWavelengthnm, pumpPowermW, Nspans, spanLengthKm)

addpath f/
addpath ../f/

verbose = false;

% Filename
filename = sprintf('results/capacity_vs_pump_power_EDF=%s_pump=%smW_%snm_L=%s_x_%skm.mat',...
        edf_type, pumpPowermW, pumpWavelengthnm, Nspans, spanLengthKm);
  
filename = check_filename(filename) % verify if already exists and rename it if it does

disp(filename) 

% convert inputs to double (on cluster inputs are passed as strings)
if ~all(isnumeric([pumpPowermW, Nspans, spanLengthKm]))
    pumpPower = 1e-3*str2double(pumpPowermW);
    pumpWavelength = 1e-9*str2double(pumpWavelengthnm);
    Nspans = round(str2double(Nspans));
    spanLength = 1e3*str2double(spanLengthKm);
end

% EDF fiber
E = EDF(10, edf_type);

% Pump & Signal
df = 50e9;
dlamb = df2dlamb(df);
lamb = 1530e-9:dlamb:1565e-9;
Pon = 1e-4;
Signal = Channels(lamb, Pon, 'forward');
Pump = Channels(pumpWavelength, pumpPower, 'forward');

% SMF fiber
SMF = fiber(spanLength, @(lamb) 0.18, @(lamb) 0);
[~, spanAttdB] = SMF.link_attenuation(Signal.wavelength);

% Problem variables
Namp = Nspans;
problem.spanAttdB = spanAttdB;
problem.Namp = Nspans;
problem.Pon = Pon;
problem.df = df;
               
% Optimize power load and EDF length
[E, Signal] = optimize_power_load_and_edf_length('particle swarm', E, Pump, Signal, problem, verbose);
                        
% Capacity calculation using numerical model
offChs = (Signal.P == 0);
Signal.P(offChs) = eps; % assign small power just for gain/noise calculations
[SE_numerical, SE_approx, num, approx] = capacity_linear_regime(E, Pump, Signal, spanAttdB, Namp, df);
Signal.P(offChs) = 0; % return to 0

fprintf('Total spectrum efficiency = %.2f bits/s/Hz\n', sum(SE_numerical));

if verbose
    figure(108)
    subplot(221), hold on, box on
    plot(Signal.wavelength*1e9, Signal.PdBm)
    xlabel('Wavelength (nm)')
    ylabel('Power (dBm)')
    xlim(Signal.wavelength([1 end])*1e9)
    
    subplot(222), hold on, box on
    hplot = plot(Signal.wavelength*1e9, num.GaindB, 'DisplayName', 'Numerical');
    plot(Signal.wavelength*1e9, approx.GaindB, '--', 'Color', get(hplot, 'Color'), 'DisplayName', 'Approximated')
    xlabel('Wavelength (nm)')
    ylabel('Gain (dB)')
    legend('-dynamicLegend', 'Location', 'Best')
    xlim(Signal.wavelength([1 end])*1e9)
    
    subplot(223), hold on, box on
    hplot = plot(Signal.wavelength*1e9, Watt2dBm(num.Pase), 'DisplayName', 'Numerical');
    plot(Signal.wavelength*1e9, Watt2dBm(approx.Pase), '--', 'Color', get(hplot, 'Color'), 'DisplayName', 'Approximated')
    xlabel('Wavelength (nm)')
    ylabel('ASE (dBm)')
    legend('-dynamicLegend', 'Location', 'Best')
    xlim(Signal.wavelength([1 end])*1e9)
    
    subplot(224), hold on, box on
    hplot = plot(Signal.wavelength*1e9, num.SE, 'DisplayName', 'Numerical');
    plot(Signal.wavelength*1e9, approx.SE, '--', 'Color', get(hplot, 'Color'), 'DisplayName', 'Approximated')
    xlabel('Wavelength (nm)')
    ylabel('Spectral efficiency (bits/s/Hz)')
    legend('-dynamicLegend', 'Location', 'Best')
    axis([Signal.wavelength([1 end])*1e9 0 ceil(max([num.SE approx.SE]))])
end

% Save to file
save(filename)