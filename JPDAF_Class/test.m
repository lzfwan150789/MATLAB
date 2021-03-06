%% Plot settings
ShowPlots = 1;
SkipFrames = 5;

%% Initiate PF parameters
nx = 4;      % number of state dims
nu = 4;      % size of the vector of process noise
nv = 2;      % size of the vector of observation noise
q  = 0.01;   % process noise density (std)
r  = 0.1;    % observation noise density (std)
% Prior PDF generator
gen_x0_cch = @(Np) mvnrnd(repmat([0,0,0,0],Np,1),diag([q^2, q^2, 100, 100]));
% Process equation x[k] = sys(k, x[k-1], u[k]);
sys_cch = @(k, xkm1, uk) [xkm1(1,:)+1*xkm1(3,:).*cos(xkm1(4,:)); xkm1(2,:)+1*xkm1(3,:).*sin(xkm1(4,:)); xkm1(3,:)+ uk(:,3)'; xkm1(4,:) + uk(:,4)'];
% PDF of process noise generator function
gen_sys_noise_cch = @(u) mvnrnd(zeros(size(u,2), nu), diag([0,0,q^2,0.16^2])); 
% Observation equation y[k] = obs(k, x[k], v[k]);
obs = @(k, xk, vk) [xk(1)+vk(1); xk(2)+vk(2)];                  % (returns column vector)
% PDF of observation noise and noise generator function
sigma_v = r;
cov_v = sigma_v^2*eye(nv);
p_obs_noise   = @(v) mvnpdf(v, zeros(1, nv), cov_v);
gen_obs_noise = @(v) mvnrnd(zeros(1, nv), cov_v);         % sample from p_obs_noise (returns column vector)
% Observation likelihood PDF p(y[k] | x[k])
% (under the suposition of additive process noise)
p_yk_given_xk = @(k, yk, xk) p_obs_noise((yk - obs(k, xk, zeros(1, nv)))');
% Assign PF parameter values
pf.k               = 1;                   % initial iteration number
pf.Np              = 5000;                 % number of particles
pf.particles       = zeros(5, pf.Np); % particles
pf.resampling_strategy = 'systematic_resampling';
pf.sys = sys_cch;
pf.particles = zeros(nx, pf.Np); % particles
pf.gen_x0 = gen_x0_cch(pf.Np);
pf.obs = p_yk_given_xk;
pf.obs_model = @(xk) [xk(1,:); xk(2,:)];
pf.R = cov_v;
pf.clutter_flag = 1;
pf.multi_flag = 1;
pf.sys_noise = gen_sys_noise_cch;

%% Set TrackNum
TrackNum = 3;

%% Generate DataList
[DataList,x1,y1] = gen_obs_cluttered_multi2(TrackNum, x_true, y_true, 0.1, 2, 10, 1);

%% Get GroundTruth
for i=1:TrackNum
    GroundTruth{i} = [x_true(:,i), y_true(:,i)]; % ith target's GroundTruth
end

%% Initiate TrackList
for i=1:TrackNum,
    pf.gen_x0 = @(Np) mvnrnd(repmat([GroundTruth{i}(1,1),GroundTruth{i}(1,2),0,0],Np,1),diag([q^2, q^2, 1, 1]));
    pf.ExistProb = 0.8;
    TrackList{i}.TrackObj = ParticleFilterMin2(pf);
end;

%% Initiate PDAF parameters
Par.Filter = ParticleFilterMin2(pf);
Par.DataList = DataList{1}(:,:);
Par.GroundTruth = GroundTruth;
Par.TrackList = TrackList;
Par.PD = 0.8;
Par.PG = 0.998;
Par.GateLevel = 5;
Par.Pbirth = 0.001;
Par.Pdeath = 0.05;
Par.SimIter = 1000;

%% Instantiate JPDAF
jpdaf = JPDAF(Par);

%% Instantiate Log to store output
N=size(DataList,2);
Logs = [];
Log.xV_ekf = zeros(nx,N);          %estmate        % allocate memory
Log.PV_ekf = zeros(1,N);
Log.sV_ekf = zeros(nx/2,N);          %actual
Log.zV_ekf = zeros(nx/2,N);
Log.eV_ekf = zeros(nx/2,N);


img = imread('maze.png');

% set the range of the axes
% The image will be stretched to this.
min_x = 0;
max_x = 10;
min_y = 0;
max_y = 10;

% make data to plot - just a line.
x = min_x:max_x;
y = (6/8)*x;

figure
for i = 1:N
    % Remove null measurements        
    jpdaf.config.DataList = DataList{i}(:,:);
    jpdaf.config.DataList( :, ~any(jpdaf.config.DataList,1) ) = [];
    jpdaf.Predict();
    
    % Compute rhi as given bu Eq. (16) in [2]
    pi = zeros(1, size(jpdaf.config.ValidationMatrix,2));
    for m = 1:size(jpdaf.config.ValidationMatrix,2)
        pi_tmp = 1;
        for t = 1:TrackNum
            pi_tmp = pi_tmp*(1-jpdaf.config.beta(t,m+1));
        end
        pi(m) = pi_tmp;
    end
    pi
    jpdaf.Update();
    TrackNum = size(TrackList,2);
    
    %store Logs
    for j=1:TrackNum
        Logs{j}.xV_ekf(:,i) = jpdaf.config.TrackList{j}.TrackObj.pf.xhk;
        st = [x1(i,j); y1(i,j)];
        Logs{j}.sV_ekf(:,i)= st;
        % Compute squared error
        Logs{j}.eV_ekf(:,i) = (jpdaf.config.TrackList{j}.TrackObj.pf.xhk(1:2,1) - st).*(jpdaf.config.TrackList{j}.TrackObj.pf.xhk(1:2,1) - st);
    end

    if (ShowPlots)
        if(i==1 || rem(i,SkipFrames+1)==0)
            % Plot data
            clf;
             % Flip the image upside down before showing it
            imagesc([min_x max_x], [min_y max_y], flipud(img));

            % NOTE: if your image is RGB, you should use flipdim(img, 1) instead of flipud.

            hold on;
            for j=1:TrackNum
                h2 = plot(Logs{j}.sV_ekf(1,1:i),Logs{j}.sV_ekf(2,1:i),'b.-','LineWidth',1);
                if j==2
                    set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
                end
                h2 = plot(Logs{j}.sV_ekf(1,i),Logs{j}.sV_ekf(2,i),'bo','MarkerSize', 10);
                set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off'); % Exclude line from legend
            end
            h2 = plot(DataList{i}(1,:),DataList{i}(2,:),'k*','MarkerSize', 10);
            for j=1:TrackNum
                colour = 'r';
                if(j==2)
                   colour = 'c';
                elseif (j==3)
                   colour = 'm';
                end
                h4 = plot(Logs{j}.xV_ekf(1,:),Logs{j}.xV_ekf(2,:),strcat(colour,'.-'),'LineWidth',1);
                %h4 = plot(Logs{j}.xV_ekf(1,i),Logs{j}.xV_ekf(2,i),strcat(colour,'o'),'MarkerSize', 10);
                c_mean = mean(jpdaf.config.TrackList{j}.TrackObj.pf.particles,2);
                c_cov = [std(jpdaf.config.TrackList{j}.TrackObj.pf.particles(1,:),jpdaf.config.TrackList{j}.TrackObj.pf.w')^2,0;0,std(jpdaf.config.TrackList{j}.TrackObj.pf.particles(2,:),jpdaf.config.TrackList{j}.TrackObj.pf.w')^2];
                h2=plot_gaussian_ellipsoid(c_mean(1:2), c_cov);
                set(h2,'color',colour);
                set(h2,'LineWidth',1);
                %plot(jpdaf.config.TrackList{j}.TrackObj.pf.particles(1,:),jpdaf.config.TrackList{j}.TrackObj.pf.particles(2,:),strcat(colour,'.'),'MarkerSize', 3);
                set(get(get(h4,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
            end
                % set the y-axis back to normal.
            set(gca,'ydir','normal');
            str = sprintf('Estimated state x_{1,k} vs. x_{2,k}');
            title(str)
            xlabel('X position (m)')
            ylabel('Y position (m)')
            h_legend = legend('Real', 'Meas', 'Target 1', 'Target 2');
            set(h_legend,'FontSize',9, 'Orientation', 'horizontal', 'Location', 'north');
            axis([0 10 0 10])
            pause(0.01)
        end
    end
end