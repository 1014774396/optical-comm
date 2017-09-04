%% Validate max_channels_on.m
clear, clc, close all

addpath ../f/

E = EDF(10, 'principles_type2');

df = 50e9;
dlamb = df2dlamb(df);
lamb = 1530e-9:dlamb:1565e-9;
L = 14e6;
SMF = fiber(50e3, @(lamb) 0.18, @(lamb) 0);
Namp = round(L/SMF.L);

Pon = 1e-4;
Signal = Channels(lamb, Pon, 'forward');
Pump = Channels(1480e-9, 50e-3, 'forward');

[~, spanAttdB] = SMF.link_attenuation(Signal.wavelength);
spanAttdB = spanAttdB*ones(size(Signal.wavelength));

problem.Pon = Pon;
problem.spanAttdB = spanAttdB;
problem.df = df;
problem.Namp = Namp;

% [Eopt_fmin, SignalOn_fmin] = optimize_power_load_and_edf_length('fminbnd', E, Pump, Signal, problem, true);
 
% [Eopt_interp, SignalOn_interp] = optimize_power_load_and_edf_length('interp', E, Pump, Signal, problem, true);

% [Eopt_pswarm, SignalOn_pswarm] = optimize_power_load_and_edf_length('particle swarm', E, Pump, Signal, problem, true);

% [Eopt_genetic, SignalOn_genetic] = optimize_power_load_and_edf_length('genetic', E, Pump, Signal, problem, true);

[Eopt_patternsearch, SignalOn_patternsearch] = optimize_power_load_and_edf_length('pattern search', E, Pump, Signal, problem, true);

