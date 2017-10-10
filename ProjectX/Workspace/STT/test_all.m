% Plot settings
ShowPlots = 1;
ShowUpdate = 0;
ShowArena = 0;
ShowPredict = 0;
SimNum = 50;
V_bounds = [0 15 0 10];

% Instantiate a Tracklist to store each filter
FilterList = [];
FilterNum = 6;

% Containers
Logs = cell(1, 5); % 4 tracks
N = size(x_true,1)-2;
for i=1:FilterNum
    Logs{i}.xV = zeros(4,N);          %estmate        % allocate memory
    Logs{i}.err = zeros(2,N);
    Logs{i}.pos_err = zeros(1,N);
    Logs{i}.exec_time = 0;
    Logs{i}.filtered_estimates = cell(1,N);
end

% Create figure windows
if(ShowPlots)
    if(ShowArena)
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
    end
    
    figure('units','normalized','outerposition',[0 0 .5 1])
    ax(1) = gca;
end



for SimIter = 1:SimNum
    % Constant Velocity Model
    config_cv.dim = 2;
    config_cv.q = 0.0001;
    CVmodel = ConstantVelocityModel(config_cv);

    % Constant Heading Model
    config.q_vel = 0.01;
    config.q_head = 0.3;
    CHmodel = ConstantHeadingModel(config);

    % Positional Observation Model
    config_meas.dim = 2;
    config_meas.r = 0.1;
    obs_model = PositionalObsModel(config_meas);

    % Initiate Kalman Filter
    config_kf.k = 1;
    config_kf.x = [x_true(2,1); y_true(2,1); x_true(2,1)-x_true(1,1); y_true(2,1)-y_true(1,1)];
    config_kf.P = CVmodel.config.Q(1);
    FilterList{1}.Filter = KalmanFilterX(config_kf, CVmodel, obs_model);

    % Initiate Extended Kalman Filter
    config_ekf.k = 1;
    config_ekf.x = [x_true(2,1); y_true(2,1); x_true(2,1)-x_true(1,1); y_true(2,1)-y_true(1,1)];
    config_ekf.P = CVmodel.config.Q(1);
    FilterList{2}.Filter = EKalmanFilterX(config_ekf, CVmodel, obs_model);

    % Initiate Unscented Kalman Filter
    config_ukf.k = 1;
    config_ukf.x = [x_true(2,1); y_true(2,1); x_true(2,1)-x_true(1,1); y_true(2,1)-y_true(1,1)];
    config_ukf.P = CVmodel.config.Q(1);
    FilterList{3}.Filter = UKalmanFilterX(config_ukf, CVmodel, obs_model);

    % Initiate Particle Filter
    config_pf.k = 1;
    config_pf.Np = 5000;
    config_pf.gen_x0 = @(Np) mvnrnd(repmat([x_true(2,1); y_true(2,1); x_true(2,1)-x_true(1,1); y_true(2,1)-y_true(1,1)]', Np,1), CHmodel.config.Q(1));
    FilterList{4}.Filter = ParticleFilterX(config_pf, CVmodel, obs_model);

    % Initiate EParticle Filter
    config_epf.k = 1;
    config_epf.Np = 5000;
    config_epf.gen_x0 = @(Np) mvnrnd(repmat([x_true(2,1); y_true(2,1); x_true(2,1)-x_true(1,1); y_true(2,1)-y_true(1,1)]', Np,1), CVmodel.config.Q(1));
    FilterList{5}.Filter = EParticleFilterX(config_epf, CVmodel, obs_model);

    % Initiate UParticle Filter
    config_upf.k = 1;
    config_upf.Np = 5000;
    config_upf.gen_x0 = @(Np) mvnrnd(repmat([x_true(2,1); y_true(2,1); x_true(2,1)-x_true(1,1); y_true(2,1)-y_true(1,1)]', Np,1), CVmodel.config.Q(1));
    FilterList{6}.Filter = UParticleFilterX(config_upf, CVmodel, obs_model);


    % Generate ground truth and measurements
    for k = 1:N
        % Generate new measurement from ground truth
        sV(:,k) = [x_true(k+2,1); y_true(k+2,1)];     % save ground truth
        zV(:,k) = obs_model.sample(0, sV(:,k),1);     % generate noisy measurment
    end

    % START OF SIMULATION
    % ===================>
    tic;
    for k = 1:N

        % Update measurements
        for i=1:FilterNum
            FilterList{i}.Filter.config.y = zV(:,k);
        end

        % Iterate all filters
        for i=1:FilterNum
            tic;
            FilterList{i}.Filter.Iterate;
            Logs{i}.exec_time = Logs{i}.exec_time + toc;
        end

        % Store Logs
        for i=1:FilterNum
            Logs{i}.err(:,k) = Logs{i}.err(:,k) + (sV(:,k) - FilterList{i}.Filter.config.x(1:2))/SimNum;
            Logs{i}.pos_err(1,k) = Logs{i}.pos_err(1,k) + sqrt((sV(1,k) - FilterList{i}.Filter.config.x(1))^2 + (sV(2,k) - FilterList{i}.Filter.config.x(2))^2)/SimNum;
            Logs{i}.xV(:,k) = FilterList{i}.Filter.config.x;
            Logs{i}.filtered_estimates{k} = FilterList{i}.Filter.config;
        end

      % Plot update step results
        if(ShowPlots && ShowUpdate)
            % Plot data
            cla(ax(1));

            if(ShowArena)
                 % Flip the image upside down before showing it
                imagesc(ax(1),[min_x max_x], [min_y max_y], flipud(img));
            end

            % NOTE: if your image is RGB, you should use flipdim(img, 1) instead of flipud.
            hold on;
            h2 = plot(ax(1),zV(1,k),zV(2,k),'k*','MarkerSize', 10);
            set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off'); % Exclude line from legend
            h2 = plot(ax(1),sV(1,1:k),sV(2,1:k),'b.-','LineWidth',1);
            set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off'); % Exclude line from legend
            h2 = plot(ax(1),sV(1,k),sV(2,k),'bo','MarkerSize', 10);
            set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off'); % Exclude line from legend

            for i=1:FilterNum
                h2 = plot(Logs{i}.xV(1,k), Logs{i}.xV(2,k), 'o', 'MarkerSize', 10);
                set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off'); % Exclude line from legend
                %plot(pf.config.particles(1,:), pf.config.particles(2,:), 'b.', 'MarkerSize', 10);
                plot(Logs{i}.xV(1,1:k), Logs{i}.xV(2,1:k), '.-', 'MarkerSize', 10);
            end
            legend('KF','EKF', 'UKF', 'PF', 'EPF', 'UPF')

            if(ShowArena)
                % set the y-axis back to normal.
                set(ax(1),'ydir','normal');
            end

            str = sprintf('Robot positions (Update)');
            title(ax(1),str)
            xlabel('X position (m)')
            ylabel('Y position (m)')
            axis(ax(1),V_bounds)
            pause(0.01);
        end
      %s = f(s) + q*randn(3,1);                % update process 
    end
end

figure
for i=1:FilterNum
    hold on;
    plot(Logs{i}.pos_err(1,:), '.-');
end
legend('KF','EKF', 'UKF', 'PF', 'EPF', 'UPF')

figure
bars = zeros(1, FilterNum);
c = categorical(c, {'KF','EKF', 'UKF', 'PF', 'EPF', 'UPF'},'Ordinal',true);
for i=1:FilterNum
    bars(i) =  Logs{i}.exec_time;
end
bar(c, bars);
%smoothed_estimates = pf.Smooth(filtered_estimates);
toc;
% END OF SIMULATION
% ===================>
