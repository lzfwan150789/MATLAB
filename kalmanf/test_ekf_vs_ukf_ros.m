%% Clear everything
%clear

%% Initiate KF parameters
n=4;      %number of state
q=0.01;    %std of process 
r=0.5;    %std of measurement
s.Q=[1^3/3, 0, 1^2/2, 0;  0, 1^3/3, 0, 1^2/2; 1^2/2, 0, 1, 0; 0, 1^2/2, 0, 1]*q^2*10; % covariance of process
s.R=r^2*eye(n/2);        % covariance of measurement  
s.sys=@(t)(@(x)[x(1)+ t*x(3); x(2)+t*x(4); x(3); x(4)]);  % nonlinear state equations
s.obs=@(x)[x(1);x(2)];                               % measurement equation
st=[x_true(1);y_true(1)];                                % initial state
s.x=[obs_x(2); obs_y(2); obs_x(2)-obs_x(1); obs_y(2)-obs_y(1)]; %initial state          % initial state with noise
s.P = eye(n);                               % initial state covraiance
x_ukf = s.x;
P_ukf = s.P;
ukf_sys = @(x,u)[5*sin(x(2)+x(3))+u(1);2*cos(x(3))+u(2);x(3)+0.1+u(3)];
ukf_obs = @(x,v)[x(1);x(2);x(3)];

N=945;                                     % total dynamic steps

% Instantiate UKF and vars to store output
xV_ukf = zeros(n,N);          %estmate        % allocate memory
PV_ukf = zeros(1,N);
%PV_ukf = cell(1,N);    % use to display ellipses 
sV_ukf = zeros(n/2,N);          %actual
zV_ukf = zeros(n/2,N);
eV_ukf = zeros(n/2,N);
ukf = UKalmanFilter(s, 0.5, 0, 2);

% Instantiate EKF and vars to store output
xV_ekf = zeros(n,N);          %estmate        % allocate memory
PV_ekf = zeros(1,N);    
%PV_ekf = cell(1,N);     % use to display ellipses 
sV_ekf = zeros(n/2,N);          %actual
zV_ekf = zeros(n/2,N);
eV_ekf = zeros(n/2,N);
ekf = EKalmanFilter(s);

%% Initiate PF parameters
% Process equation x[k] = sys(k, x[k-1], u[k]);
nx = 4;  % number of states
sys = @(k, xkm1, uk) [xkm1(1)+1*xkm1(3)+ uk(1); xkm1(2)+1*xkm1(4) + uk(2); xkm1(3)+ uk(3); xkm1(4) + uk(4)]; % (returns column vector)

% Observation equation y[k] = obs(k, x[k], v[k]);
ny = 2;                                           % number of observations
obs = @(k, xk, vk) [xk(1)+vk(1); xk(2)+vk(2)];                  % (returns column vector)

% PDF of process noise and noise generator function
nu = 4;                                           % size of the vector of process noise
sigma_u = 0.01;
cov_u = [1^3/3, 0, 1^2/2, 0;  0, 1^3/3, 0, 1^2/2; 1^2/2, 0, 1, 0; 0, 1^2/2, 0, 1]*10*sigma_u^2;
p_sys_noise   = @(u) mvnpdf(u, zeros(1, nu), cov_u);
gen_sys_noise = @(u) mvnrnd(zeros(1, nu), cov_u);         % sample from p_sys_noise (returns column vector)

% PDF of observation noise and noise generator function
nv = 2;                                           % size of the vector of observation noise
sigma_v = 0.5;
cov_v = sigma_v^2*eye(nv);
p_obs_noise   = @(v) mvnpdf(v, zeros(1, nv), cov_v);
gen_obs_noise = @(v) mvnrnd(zeros(1, nv), cov_v);         % sample from p_obs_noise (returns column vector)

% Initial PDF
% p_x0 = @(x) normpdf(x, 0,sqrt(10));             % initial pdf
gen_x0 = @(x) mvnrnd([obs_x(2); obs_y(2); obs_x(2)-obs_x(1); obs_y(2)-obs_y(1)],cov_u);               % sample from p_x0 (returns column vector)

% Transition prior PDF p(x[k] | x[k-1])
% (under the suposition of additive process noise)
% p_xk_given_xkm1 = @(k, xk, xkm1) p_sys_noise(xk - sys(k, xkm1, 0));

% 
% (under the suposition of additive process noise)
p_yk_given_xk = @(k, yk, xk) p_obs_noise((yk - obs(k, xk, zeros(1, nv)))');

% Number of time steps
T = 945;

% Separate memory space
x = zeros(nx,T);  y = zeros(ny,T);
u = zeros(nu,T);  v = zeros(nv,T);

% Simulate system
xh0 = [obs_x(2); obs_y(2); obs_x(2)-obs_x(1); obs_y(2)-obs_y(1)]                                  % initial state
u(:,1) = gen_sys_noise(sigma_u)';                               % initial process noise
v(:,1) = gen_obs_noise(sigma_v)';          % initial observation noise
x(:,1) = xh0;
y(:,1) = obs(1, xh0, v(:,1));
for k = 2:T
   % here we are basically sampling from p_xk_given_xkm1 and from p_yk_given_xk
   u(:,k) = gen_sys_noise();              % simulate process noise
   v(:,k) = gen_obs_noise();              % simulate observation noise
   x(:,k) = sys(k, x(:,k-1), u(:,k));     % simulate state
   y(:,k) = obs(k, x(:,k),   v(:,k));     % simulate observation
end
x = [x_true, y_true]';
y = [obs_x'; obs_y'];
% Separate memory
xh = zeros(nx, T); xh(:,1) = xh0;
yh = zeros(ny, T); yh(:,1) = obs(1, xh0, zeros(1, nv));

pf.k               = 1;                   % initial iteration number
pf.Np              = 1000;                 % number of particles
%pf.w               = zeros(pf.Np, T);     % weights
pf.particles       = zeros(nx, pf.Np, T); % particles
pf.gen_x0          = gen_x0;              % function for sampling from initial pdf p_x0
pf.obs             = p_yk_given_xk;       % function of the observation likelihood PDF p(y[k] | x[k])
pf.sys_noise       = gen_sys_noise;       % function for generating system noise
%pf.p_x0 = p_x0;                          % initial prior PDF p(x[0])
%pf.p_xk_given_ xkm1 = p_xk_given_xkm1;   % transition prior PDF p(x[k] | x[k-1])
pf.xhk = xh0;
pf.sys = sys;
pf.resampling_strategy = 'systematic_resampling';
my_pf = ParticleFilter(s);
%% Track
figure
for k=1:N
    ukf.s.sys = s.sys(1);
    st = [x_true(k); y_true(k)];
    %% Get next measurement
    ukf.s.z = [obs_x(k); obs_y(k)];                     % measurments
    ekf.s.z = ukf.s.z;

    %% Store new state and measurement
    sV_ukf(:,k)= [x_true(k); y_true(k)];                             % save actual state
    zV_ukf(:,k)  = ukf.s.z;                             % save measurment
    sV_ekf(:,k)= st;                             % save actual state
    zV_ekf(:,k)  = ekf.s.z; 

    %% Iterate both filters
    ekf.s.sys = s.sys(1);
    ekf.s = ekf.Iterate(ekf.s);
    %ukf.s.sys = s.sys(N);
    %[x_ukf, P_ukf] = ukf_fl(ukf_sys, ukf_obs, ekf.s.z, x_ukf, P_ukf,  s.Q, s.R);
    ukf.s = ukf.Iterate(ukf.s);            % ekf 

    %% Store estimated state and covariance
    xV_ukf(:,k) = ukf.s.x;%x_ukf;                            % save estimate
    PV_ukf(k)= ukf.s.P(1,1); % P_ukf(1,1) ; 
    %PV_ukf{k}= ukf.s.P;    % Use to store whole covariance matrix
    xV_ekf(:,k) = ekf.s.x;                            % save estimate
    PV_ekf(k) = ekf.s.P(1,1);
    %PV_ekf{k} = ekf.s.P;    % Use to store whole covariance matrix

    %% Compute squared error
    eV_ukf(:,k) = (ukf.s.x(1:2,1) - st).*(ukf.s.x(1:2,1) - st);
    eV_ekf(:,k) = (ekf.s.x(1:2,1) - st).*(ekf.s.x(1:2,1) - st);

    clf;
    hold on;
    h2 = plot(sV_ukf(1,1:k),sV_ukf(2,1:k),'b','LineWidth',1);
   h3 = plot(xV_ukf(1,1:k),xV_ukf(2,1:k),'r','LineWidth',1);
   h4 = plot(xV_ekf(1,1:k),xV_ekf(2,1:k),'c','LineWidth',1);
   h5 = plot(zV_ukf(1,1:k), zV_ukf(2,1:k),'g.','LineWidth',1);
   legend([h2 h3 h4 h5],'state','UKF', 'EKF','measurements');
   title('State vs estimated state by the particle filter vs particle paths','FontSize',14);
    pause(0.1)
    %% Generate new state
    %st = ukf.s.sys(st)+q*(-1 + 2*rand(3,1));                % update process 
end

%% Compute & Print RMSE
RMSE_ukf = sqrt(sum(eV_ukf,2)/N)
RMSE_ekf = sqrt(sum(eV_ekf,2)/N)


%% Plot results
figure
for k=1:2                                 % plot results
    subplot(3,1,k)
%     figure
%     hold on
    plot(1:N, sV_ukf(k,:), 'k--', 1:N, xV_ukf(k,:), 'b-',1:N, xV_ekf(k,:), 'g-', 1:N, zV_ukf(k,:), 'r.')
%     for i = 1:N
%         hold on
%         error_ellipse('C', blkdiag(PV_ukf{i}(1,1),1), 'mu', [i, xV_ukf(k,i)], 'style', 'r--')
%         hold on
%         error_ellipse('C', blkdiag(PV_ekf{i}(1,1),1), 'mu', [i, xV_ekf(k,i)], 'style', '--')
%     end
    str = sprintf('EKF vs UKF estimated state X(%d)',k);
    title(str)
    legend('Real', 'UKF', 'EKF', 'Meas');
end
subplot(3,1,3)
plot(1:N, PV_ukf(:,:), 1:N, PV_ekf(:,:))
title(sprintf('EKF vs UKF estimated covariance P(1,1)',k))
legend('UKF', 'EKF');

figure
plot(sV_ukf(1,:), sV_ukf(2,:),xV_ukf(1,:), xV_ukf(2,:), xV_ekf(1,:), xV_ekf(2,:));
title(sprintf('EKF vs UKF estimated covariance P(1,1)',k))
legend('true', 'UKF', 'EKF');

