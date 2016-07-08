classdef PAM
    %% Class PAM
    properties
        M % constellation size
        Rb % bit rate
        level_spacing % 'equally-spaced' or 'optimized'
        pulse_shape % struct containing the following fields {type: {'rectangular', 'root raised cosine', 'raised cosine'}, h: pulse shape impulse response i.e., coefficients of FIR filter,sbs: samples per symbol, and other parameters such as rolloff factor, etc}
        a % levels
        b % decision threshold
    end
    
    properties (Dependent)
        Rs % symbol rate
        optimize_level_spacing % logical variable
    end
    
    properties (GetAccess=private)
        % Used in level spacing optimization
        maxtol = 1e-6; % maximum tolerance for convergence
        maxBERerror = 1e-3; % maximum acceptable BER error in level spacing optimization
        maxit = 20; % maximum number of iteratios
    end
       
    methods
        function obj = PAM(M, Rb, level_spacing, pulse_shape)
            %% Class constructor
            % Inputs
            % - M = constellation size
            % - Rb = bit rate
            % - level_spacing = 'equally-spaced' or 'optimized'
            % - puse_shape = % struct containing the following fields {type:
            % {'rectangular', 'root raised cosine', 'raised cosine'}, 
            % h: pulse shape impulse response i.e., coefficients of FIR filter,
            % Mct: oversampling ratio of pulse shapping filter, and
            % other parameters such as rolloff factor, etc}
            
            obj.M = M;
            obj.Rb = Rb;
            obj.level_spacing = level_spacing;
            assert(~strcmp(class(pulse_shape), 'function_handle'), 'PAM: behaviour of PAM has changed. Now PAM expects a struct as opposed to the function handle.')
            obj.pulse_shape = pulse_shape;
            obj.pulse_shape.h = obj.norm_filter_coefficients(obj.pulse_shape.h);
            
            switch level_spacing
                case 'equally-spaced'
                    obj.a = ((0:2:2*(M-1))/(2*(M-1))).';
                    obj.b = ((1:2:(2*(M-1)-1))/(2*(M-1))).';
                case 'optimized'
                    % Optimize level spacing function must be called
                    obj.a = []; 
                    obj.b = [];
                otherwise
                    error('pam class: Invalid level spacing option')
            end
        end
        
        function PAMtable = summary(self)
            %% Generate table summarizing class values
            disp('PAM class parameters summary:')
            rows = {'PAM order'; 'Symbol rate'; 'Level spacing'; 'Pulse shape'};
            Variables = {'M'; 'Rs'; 'level_spacing'; 'pulse_shape.type'};
            Values = {self.M; self.Rs; self.level_spacing; self.pulse_shape.type};
            Units = {''; 'Gbaud'; ''; ''};

            PAMtable = table(Variables, Values, Units, 'RowNames', rows);
        end
        
        %% Get methods
        function Rs = get.Rs(self)
            %% Symbol-rate assuming rectangular pulse
            Rs = self.Rb/log2(self.M);
        end
        
        function optimize_level_spacing = get.optimize_level_spacing(self)
            %% True if level_spacing == 'optimized'
            optimize_level_spacing = strcmp(self.level_spacing, 'optimized');
        end
        
        %% Auxiliary functions       
        function self = set_levels(self, levels, thresholds)
            %% Set levels to desired values
            % Levels and decision thresholds are normalized that last level is unit
            assert(length(levels) == self.M, 'mpam/set_levels: invalid number of levels');
            assert(length(thresholds) == self.M-1, 'mpam/set_levels: invalid number of decision thresholds');
            if size(levels, 1) < size(levels, 2) % ensure levels are M x 1 vector
                levels = levels.'; 
            end
            if size(thresholds, 1) < size(thresholds, 2)  % ensure thresholds are M x 1 vector
                thresholds = thresholds.';
            end
                
            self.a = levels;
            self.b = thresholds;
        end
        
        function self = norm_levels(self)
            %% Normalize levels so that last level is 1
            self.b = self.b/self.a(end);
            self.a = self.a/self.a(end);
        end
                    
        function self = adjust_levels(self, Ptx, rexdB)
            %% Adjust levels to desired transmitted power and extinction ratio
            % Inputs:
            % - Ptx = transmitted power (W)
            % - rexdB = extinction ratio (dB). Defined as Pmin/Pmax
            % Outputs:
            % - Plevels, Pthresh = result levels and decision thresholds,
            % respectively.
            
            rex = 10^(-abs(rexdB)/10); % extinction ratio. Defined as Pmin/Pmax
            switch self.level_spacing
                case 'equally-spaced'
                    % Restart levels
                    self.a = ((0:2:2*(self.M-1))/(2*(self.M-1))).';
                    self.b = ((1:2:(2*(self.M-1)-1))/(2*(self.M-1))).';
                    
                    amean = mean(self.a); % mean value
                    
                    Pmin = 2*Ptx*rex/(1 + rex); % power of the lowest level 
                    Plevels = self.a*(Ptx/amean)*((1-rex)/(1+rex)) + Pmin; % levels at the transmitter
                    Pthresh = self.b*(Ptx/amean)*((1-rex)/(1+rex)) + Pmin; % decision thresholds at the transmitter
                case 'optimized'
                    amean = mean(self.a); % mean value
                    
                    % Extinction ratio was already enforced in the
                    % optimization process, so just scale to desired power
                    Plevels = self.a*Ptx/amean; % levels at the transmitter
                    Pthresh = self.b*Ptx/amean; % decision thresholds at the transmitter
                otherwise
                    error('pam class: Invalid level spacing option')
            end
            
            self.a = Plevels;
            self.b = Pthresh;            
        end       
        
        function h = norm_filter_coefficients(~, h)
            %% Normalize coefficients of FIR filter h so that impulse response of h at t = 0 is 1
            n = length(h);
            if mod(n, 2) == 0 % even
                h = 2*h/(h(n/2) + h(n/2+1));
            else
                h = h/h((n+1)/2);
            end
                
        end
        
        function [xt, xd] = signal(self, dataTX)
            %% Generate PAM signal
            % Note: group delay due to pulse shaping filtering is not
            % removed
            % Input:
            % - dataTX = transmitted symbols from 0 to M-1
            % Outputs:
            % - xt = pulse shaped PAM signal with oversampling ratio = mpam.pulse_shape.sps (1 x length(dataTX)*mpam.pulse_shape.sps)
            % - xd = symbols at symbol rate (1 x length(dataTX))
            
            % Normalize filter taps to preserve levels amplitude           
            self.pulse_shape.h = self.norm_filter_coefficients(self.pulse_shape.h);
            % Generate data, upsample, filter, and remove group delay
            xd = self.mod(dataTX); % 1 x length(dataTX)
            ximp = upsample(xd, self.pulse_shape.sps);
            xt = filter(self.pulse_shape.h, 1, ximp); 
        end
        
        function xd = mod(self, dataTX)
            %% Generate PAM symbols
            % Input:
            % - dataTX = transmitted symbols from 0 to M-1
            % Outputs:
            % - xd = symbols at symbol rate (1 x length(dataTX))            
            xd = self.a(gray2bin(dataTX, 'pam', self.M) + 1).'; % 1 x length(dataTX)
        end
        
        function dataRX = demod(self, yd)
            %% Demodulate PAM signal
            % Input:
            % - y = PAM signal at symbol rate
            % Output:
            % - dataRX = detected symbols
            dataRX = sum(bsxfun(@ge, yd(:), self.b.'), 2);
            dataRX = bin2gray(dataRX, 'pam', self.M).';
        end
        
        function [ber, berk] = ber_awgn(self, noise_std)
            %% Alias for berAWGN
            warning('mpam/ber_awgn: use berAWGN(noise_std) instead of ber_awgn(noise_std)')
            [ber, berk] = self.berAWGN(noise_std);
        end
        
        function [ber, berk] = berAWGN(self, noise_std)
            %% Calculate BER in AWGN channel where the noise standard deviation is given by the function noise_std
            % Input:
            % - noise_std = handle function that calculates the noise std for
            % a given signal level
            % Outputs:
            % - ber = total ber
            % - berk = ber of the kth level. self actually corresponds to 
            % bertail_levels = p(error | given symbol)p(symbol)
            ser = zeros(1, self.M);
            for k = 1:self.M
                if k == 1
                    ser(k) = ser(k) + qfunc((self.b(1) - self.a(1))/noise_std(self.a(1)));
                elseif k == self.M
                    ser(k) = ser(k) + qfunc((self.a(k) - self.b(k-1))/noise_std(self.a(k)));
                else
                    ser(k) = ser(k) + qfunc((self.b(k) - self.a(k))/noise_std(self.a(k)));
                    ser(k) = ser(k) + qfunc((self.a(k) - self.b(k-1))/noise_std(self.a(k)));
                end
            end

            ser = ser/self.M;
            
            berk = ser/log2(self.M); % self corresponds to p(error | given symbol)p(symbol)
            ber = sum(berk);
        end
        
        function PreqdBm = required_power(self, N0, BERtarget)
            %% Required received power to achieve target BER for a thermal noise limited receiver with N0
            % Responsivity is assumed to be 1
            R = 1;
            Preq = (self.M-1)*sqrt(self.Rb*N0/(2*R^2*log2(self.M)))*qfuncinv(self.M*BERtarget*log2(self.M)/(2*(self.M-1)));
            PreqdBm = 10*log10(Preq/1e-3);      
            
            BER = 1/log2(self.M)*2*(self.M-1)/self.M*qfunc(sqrt(log2(self.M)/((self.M-1)^2)*Preq^2/(self.Rb*N0/2)))
            
        end
        
        function self = optimize_level_spacing_gauss_approx(self, BERtarget, rexdB, noise_std, verbose)
            %% Level spacing (a) and decision threshold (b) optmization
            % Assumes infinite extinction ratio at first, then corrects power and
            % optmize levels again
            % The levels and thresholds calculated are at the receiver
            % (i.e., after any amplification)
            % Error probability under a single tail for a given symbol
            % Inputs:
            % - BERtarget = target BER
            % - rexdB = extinction ratio (dB). Defined as Pmin/Pmax
            % - noise_std = handle function that calculates the noise std for
            % a given signal level
            % - verbose = whether to plot algorithm convergence curve
            % Outputs:
            % - aopt, bopt = optimized levels and decision thresholds, 
            % respectively.
            
            % Error probability
            Pe = log2(self.M)*BERtarget*(self.M/(2*(self.M-1)));

            % Initialize levels and thresholds
            aopt = zeros(self.M, 1);
            bopt = zeros(self.M-1, 1);

            rex = 10^(-abs(rexdB)/10);

            tol = Inf;
            k = 1;
            while tol(end) > self.maxtol && k < self.maxit
                apast = aopt;
                aopt(1) = aopt(end)*rex;

                for level = 1:self.M-1
                    % Find threshold
                    sig = noise_std(aopt(level));

                    [dPthresh, ~, exitflag] = fzero(@(dPthresh) qfunc(abs(dPthresh)/sig) - Pe, 0);

                    if exitflag ~= 1
                        warning('level_spacing_optm: threshold optimization did not converge');
                    end

                    bopt(level) = aopt(level) + abs(dPthresh);

                    % Find next level  
                    [dPlevel, ~, exitflag] = fzero(@(dPlevel) qfunc(abs(dPlevel)/noise_std(bopt(level) + abs(dPlevel))) - Pe, 0);    

                    if exitflag ~= 1
                        warning('level_spacing_optm: level optimization did not converge');     
                    end

                    aopt(level+1) = bopt(level) + abs(dPlevel);
                end

                tol(k) = sqrt(sum(abs(aopt-apast).^2));
                k = k + 1;       
            end
            
            self.b = bopt;
            self.a = aopt;

            BERerror = abs(self.ber_awgn(noise_std) - BERtarget)/BERtarget;
            if  BERerror > self.maxBERerror
                warning('PAM>optimize_level_spacing_gauss_approx: BER error %g greater than maximum acceptable error\n', BERerror);
            end                

            if nargin == 5 && verbose
                figure, hold on
                plot(log(tol))
                plot([1 k], log(self.maxtol*[1 1]), 'r')
                xlabel('Iteration')
                ylabel('log(Tolerance)')
                legend('Tolerance', 'Required for Convergence')
                title('Level optimization convergece')
            end 
        end       
    end
        
    %% Validation methods
    methods
        function validate_pulse_shape(self)
            Mct = self.pulse_shape.sps;
            dataTX = randi([0 self.M-1], [1 1024]);
            xt = self.signal(dataTX);
            
            eyediagram(xt, 2*Mct)
            title('Eye diagram')
            figure, box on
            self.pulse_shape.h = self.norm_filter_coefficients(self.pulse_shape.h); % normalize to preserve levels amplitude
            [H, w] = freqz(self.pulse_shape.h, 1);
            plot(w/(2*pi), abs(H).^2)
            xlabel('Normalized frequency (Hz)')
            ylabel('Amplitude')
            title('Frequency response of pulse shaping filter')
        end
    end
end