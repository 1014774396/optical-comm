classdef fiber < handle
    %% Single-mode fiber
    properties
        L % fiber length (m)
        att % attenuation function i.e., alpha = att(lambda) (dB/km)
        D % dispersion function i.e., Dispersion = D(lambda)
        PMD = false; % whether PMD is included in simulations
        meanDGDps = 0.1; % mean DGD in ps/sqrt(km)
        PMD_section_length = 1e3  % Section length for simulating PMD (m)
        PDL = 0 % polarization dependent loss (dB). Here, it indicates how much the y pol will be attenuated with respect to x pol
    end
    
    properties(GetAccess=private, Dependent)
        JonesMatrix % Jones Matrix 
    end
    
    properties(Constant)
        S0 = 0.092*1e3;     % dispersion slope (in s/m^3)
        lamb0 = 1310e-9;   % zero-dispersion wavelength
    end
    
    properties(Constant, GetAccess=private)
        c = 299792458;  % speed of light
    end    

    methods
        function obj = fiber(L, att, D)
            %% Class constructor 
            % Inputs: 
            % - L = fiber length (m)
            % - att (optional, default is no attenuation) function handle of 
            % fiber attenuation (dB/km) as a function of the wavelength. 
            % - D (optional, default is dispersion of standard SMF) = 
            % function handle of fiber chromatic dispersion (s/m^2) as a 
            % function of the wavelength.
            if nargin >=1
                obj.L = L;
            else
                obj.L = 0;
            end
            
            if nargin >= 2
                obj.att = att;
            else % assumes constant attenuation of 0 dB/km
                obj.att = @(lamb) 0;
            end
            
            if nargin == 3
                obj.D = D;
            else % assume SMF28 with zero-dispersion wavelength = 1310nm and slope S0 = 0.092         
                obj.D = @(lamb) fiber.S0/4*(lamb - fiber.lamb0^4./(lamb.^3)); % Dispersion curve
            end           
        end
             
        %% Main Methods
        function N = Ntaps(self, Rs, lambda)
            %% Estimated number of taps in DSP required to compensate for CD in coherent detection link
            N = 2*self.L*abs(self.D(lambda))*Rs^2*lambda^2/self.c;
        end
        
        function b2 = beta2(this, lamb)
            %% Calculates beta2 at wavelength lamb
            b2 = -this.D(lamb).*(lamb.^2)/(2*pi*this.c); 
        end    
        
        function [link_att, link_attdB] = link_attenuation(this, lamb)
            %% Calculate link attenuation in linear units
            % Input:
            % - lamb = wavelength (m)
            link_att = 10^(-this.att(lamb)*this.L/1e4);
            link_attdB = this.L/1e3*this.att(lamb);
        end

        function Eout = linear_propagation(this, Ein, f, lambda)
            %% Linear propagation including only dispersion and first-order PMD if pmd flag is set and input signal has 2 dimensions
            % Perform linear propagation including chromatic dispersion,
            % and attenuation
            % Inputs: 
            % - Ein = input electric field
            % - f = frequency vector (Hz)
            % - lambda = wavelength (m)
            % Outputs: 
            % - Eout, Pout = output electric field and optical power
            % respectively.
            
            if this.L == 0
                Eout = Ein;
                return
            end
            
            two_pols = false;
            if all(size(Ein) >= 2) % two pols
                two_pols = true;
                if size(Ein, 1) > size(Ein, 2)
                    Ein = Ein.';
                end
                Einf = fftshift(fft(Ein, [], 2), 2);
            else
                Einf = fftshift(fft(Ein));
            end
            
            % PMD
            if this.PMD
                if isempty(this.JonesMatrix)
                    this.generateJonesMatrix(2*pi*f); % 2 x 2 x length(f)
                end

                for k = 1:length(f)
                    Einf(:, k) = this.JonesMatrix(:,:,k)*Einf(:, k);
                end
            end

            % Chromatic dispersion
            Hele = this.Hdisp(f, lambda);
            if two_pols
                Eout = Einf;
                Eout(1, :) = ifft(ifftshift(Hele.*Einf(1, :)));
                Eout(2, :) = ifft(ifftshift(Hele.*Einf(2, :)));
            else
                Eout = ifft(ifftshift(Hele.*Einf));
            end

            % PDL
            if two_pols && this.PDL ~= 0
                a = 10^(-this.PDL/10);
                Eout(2, :) = a*Eout(2, :);
            end
            
            % Received power 
            Eout = Eout*sqrt(this.link_attenuation(lambda));
        end
        
        function Hele = Hdisp(this, f, lambda)
            %% Dispersion frequency response Hele(f) = Eout(f)/Ein(f)
            % Inputs: 
            % - f = frequency vector (Hz)
            % - lambda = wavelength (m)
            % Outputs:
            % - Hele = Eout(f)/Ein(f)
            
            beta2 = this.beta2(lambda);
            w = 2*pi*f;
            Dw = -1j*1/2*beta2*(w.^2);
            Hele = exp(this.L*Dw);
        end
               
        function Hf = H(this, f, tx)
            %% Fiber small-signal frequency response assuming transient chirp dominant
            % This transfer function is for optical power not electic field
            % i.e., Hfiber(f) = Pout(f)/Pin(f).
            % Inputs:
            % - f = frequency vector (Hz)
            % - tx = transmitter struct. Required fields: lamb (wavelenth
            % in m), and alpha (optional, default zero) (chirp paramter). 
                        
            beta2 = this.beta2(tx.lamb);

            % CD frequency response
            theta = -1/2*beta2*(2*pi*f).^2*this.L; % theta = -1/2*beta2*w.^2*L

            if isfield(tx, 'alpha') % if chirp parameter is defined
                alpha = tx.alpha;
            else
                alpha = 0;
            end
            
            Hf = cos(theta) - alpha*sin(theta);  % fiber small-signal frequency response
        end
        
        function Hf = Hlarge_signal(self, f, tx)
            %% Fiber large-signal frequency response assuming transient chirp dominant
            % Peral, E., Yariv, A., & Fellow, L. (2000). Large-Signal Theory of the Effect
            % of Dispersive Propagation on the Intensity Modulation Response of Semiconductor Lasers. 
            % Journal of Lightwave Technology, 18(1), 84�89.
            % This transfer function is for optical power not electic field
            % i.e., Hfiber(f) = Pout(f)/Pin(f).
            % Inputs:
            % - f = frequency vector (Hz)
            % - tx = transmitter struct. Required fields: lamb (wavelenth
            % in m), and alpha (optional, default zero) (chirp paramter).
            beta2 = self.beta2(tx.lamb);

            % CD frequency response
            theta = -1/2*beta2*(2*pi*f).^2*self.L; % theta = -1/2*beta2*w.^2*L

            if isfield(tx, 'alpha') % if chirp parameter is defined
                alpha = tx.alpha;
            else
                alpha = 0;
            end
            
            mIM = 1; % assumes worst case i.e., signal fully modulated
            Dphi = pi/2; % i.e., transient chirp dominant
            mFM = alpha/2*mIM;
            u = 2*mFM*sin(theta);
            Hf = cos(theta).*(besselj(0, u) - besselj(2, u)*exp(1j*Dphi)) - 2*exp(1j*Dphi)/(1j*mIM)*besselj(1, u);  % fiber large-signal frequency response                       
        end
        
        function tau = calcDGD(self, omega)
            %% Calculate differential group delay from Jones Matrix
            if ~self.PMD 
                tau = zeros(size(omega));
                warning('fiber/calcDGD: PMD is disable')
                return
            end
                
            if isempty(self.JonesMatrix)
                tau = [];
                warning('fiber/calcDGD: Jones Matrix was not calculated yet')
                return
            end
            
            tau = zeros(1,length(omega)-1);
            dw = abs(omega(1)-omega(2));
            for m = 1:length(omega)-1;
                tau(m) = 2/dw*sqrt(det(self.JonesMatrix(:,:,m+1)-self.JonesMatrix(:,:,m)));
            end
         end
        
    end  

    methods(Access=private)
        function M = generateJonesMatrix(self, omega)
            %% Function to generate Jones Matrix, modified from Milad Sharif's code
            Nsect = ceil(self.L/self.PMD_section_length);
            
            tauDGD = self.meanDGDps*1e-12*self.L/1e3; % corresponds to total 
            
            dtau = tauDGD/sqrt(Nsect);

            U = randomRotationMatrix();

            M = repmat(U,[1,1,length(omega)]);

            for k = 1:Nsect
                U = randomRotationMatrix();

                for m = 1:length(omega)
                    Dw = [exp(1j*dtau*omega(m)/2), 0; 0, exp(-1j*dtau*omega(m)/2)]; % Birefringence matrix
                    M(:,:,m) = M(:,:,m)*U'*Dw*U;
                end
            end

            function U = randomRotationMatrix()
                phi = rand(1, 3)*2*pi;
                U1 = [exp(-1j*phi(1)/2), 0; 0 exp(1j*phi(1)/2)];
                U2 = [cos(phi(2)/2) -1j*sin(phi(2)/2); -1j*sin(phi(2)/2) cos(phi(2)/2)];
                U3 = [cos(phi(3)/2) -sin(phi(3)/2); sin(phi(3)/2) cos(phi(3)/2)];

                U = U1*U2*U3;
            end
            
            this.JonesMatrix = M;
        end
    end
        

    
end
        