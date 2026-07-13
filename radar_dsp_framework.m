%% =========================================================================
%  SECTION 0: GLOBAL CONFIGURATION (edit here to reconfigure system)
% =========================================================================
cfg = struct();

% --- Radar & Signal Parameters ---
cfg.fc          = 10e9;         % Carrier frequency [Hz] (X-band)
cfg.c           = 3e8;          % Speed of light [m/s]
cfg.fs          = 200e6;        % Sampling frequency [Hz]
cfg.B           = 50e6;         % Chirp bandwidth [Hz]
cfg.T           = 10e-6;        % Pulse duration [s]
cfg.PRI         = 200e-6;       % Pulse repetition interval [s]
cfg.N_pulses    = 16;           % Number of coherent pulses (CPI)

% --- Scene Parameters ---
cfg.target_ranges  = [1500, 1520, 3000];   % Target ranges [m]
cfg.target_rcs     = [1.0,  0.8,  1.5];    % Radar cross section [m^2]
cfg.target_vel     = [30,   -20,  0];       % Radial velocity [m/s]

% --- Noise & Clutter Parameters ---
cfg.SNR_dB         = 20;        % Input SNR [dB]
cfg.clutter_power  = 0.05;       % Clutter power relative to noise
cfg.clutter_type   = 'nonstationary'; % 'white' | 'nonstationary' | 'none'

% --- Processing Choices (change these to explore trade-offs) ---
cfg.waveform_type  = 'LFM';     % 'LFM' | 'PhaseCode' | 'Hybrid'
cfg.window_type    = 'hamming'; % 'none' | 'hamming' | 'hanning' | 'chebyshev' | 'blackman'
cfg.cfar_type      = 'CA';      % 'fixed' | 'CA' | 'OS' | 'GO'
cfg.clutter_filter = 'MTI';     % 'none' | 'MTI' | 'Doppler' | 'Adaptive'
cfg.swerling_model = 1;         % 0 (non-fluctuating) | 1 | 2 | 3 | 4

% --- CFAR Parameters ---
cfg.cfar_guard      = 4;        % Guard cells each side
cfg.cfar_train      = 10;       % Training cells each side
cfg.cfar_pfa        = 1e-4;     % Desired Pfa
cfg.fixed_threshold = 0.5;      % Fixed threshold (normalized)

% --- FFT & Range Parameters ---
cfg.NFFT        = 1024;         % FFT size
cfg.lambda      = cfg.c / cfg.fc;  % Wavelength [m]
cfg.range_res   = cfg.c / (2*cfg.B);    % Range resolution [m]
cfg.max_range   = cfg.c * cfg.PRI / 2;  % Maximum unambiguous range [m]

% --- Global Dark Theme Plotting Defaults ---
set(groot, 'DefaultFigureColor', 'k');
set(groot, 'DefaultAxesColor', 'k');
set(groot, 'DefaultAxesXColor', 'w');
set(groot, 'DefaultAxesYColor', 'w');
set(groot, 'DefaultAxesZColor', 'w');
set(groot, 'DefaultTextColor', 'w'); % Automatically styles plot titles and labels white
set(groot, 'DefaultLegendColor', 'none');
set(groot, 'DefaultLegendTextColor', 'w');
set(groot, 'DefaultLegendEdgeColor', 'w');
set(groot, 'DefaultAxesGridColor', 'w');

fprintf('\n==========================================================\n');
fprintf('  CE363 Radar DSP Framework — SPRING 2026\n');
fprintf('==========================================================\n');
fprintf('  Waveform  : %s\n', cfg.waveform_type);
fprintf('  Window    : %s\n', cfg.window_type);
fprintf('  CFAR      : %s-CFAR\n', cfg.cfar_type);
fprintf('  Clutter   : %s\n', cfg.clutter_filter);
fprintf('  Swerling  : Model %d\n', cfg.swerling_model);
fprintf('  Range Res : %.2f m\n', cfg.range_res);
fprintf('  Max Range : %.1f km\n', cfg.max_range/1e3);
fprintf('==========================================================\n\n');

%% =========================================================================
%  SECTION 1: WAVEFORM GENERATION
% =========================================================================
fprintf('[1/9] Generating %s waveform...\n', cfg.waveform_type);

N_samp = round(cfg.T * cfg.fs);   % samples per pulse
t_pulse = (0:N_samp-1) / cfg.fs;  % time vector

switch cfg.waveform_type
    case 'LFM'
        tx = generate_LFM(t_pulse, cfg.B, cfg.T);
    case 'PhaseCode'
        tx = generate_PhaseCode(N_samp, 'Barker13');
    case 'Hybrid'
        tx = generate_Hybrid(t_pulse, cfg.B, cfg.T, N_samp);
    otherwise
        error('Unknown waveform type: %s', cfg.waveform_type);
end

figure('Name','Waveform Analysis','NumberTitle','off','Color','k');
subplot(3,1,1);
plot(t_pulse*1e6, real(tx), 'b', 'LineWidth',1.2);
xlabel('Time (\mus)'); ylabel('Amplitude');
title(sprintf('%s Waveform — Real Part', cfg.waveform_type));
grid on;

subplot(3,1,2);
[Pxx, f_ax] = periodogram(tx, [], cfg.NFFT, cfg.fs, 'centered');
plot(f_ax/1e6, 10*log10(Pxx), 'r', 'LineWidth',1.2);
xlabel('Frequency (MHz)'); ylabel('PSD (dB/Hz)');
title('Transmitted Signal Spectrum'); grid on;

subplot(3,1,3);
plot(t_pulse*1e6, unwrap(angle(tx))*180/pi, 'm', 'LineWidth',1.2);
xlabel('Time (\mus)'); ylabel('Phase (degrees)');
title('Instantaneous Phase'); grid on;

%% =========================================================================
%  SECTION 2: AMBIGUITY FUNCTION ANALYSIS
% =========================================================================
fprintf('[2/9] Computing ambiguity function...\n');

[AF, delay_axis, doppler_axis] = compute_ambiguity(tx, cfg.fs, cfg.lambda);

figure('Name','Ambiguity Function','NumberTitle','off','Color','k');
subplot(1,2,1);
imagesc(delay_axis*1e6, doppler_axis/1e3, 20*log10(abs(AF)+eps));
xlabel('Delay (\mus)'); ylabel('Doppler (kHz)');
title(sprintf('Ambiguity Function: %s', cfg.waveform_type));
colorbar; axis xy;
caxis([-50 0]);

subplot(1,2,2);
% Zero-Doppler cut (range profile)
zero_dop_idx = round(size(AF,1)/2);
AF_range = abs(AF(zero_dop_idx,:));
AF_range = AF_range / max(AF_range);
plot(delay_axis*1e6, 20*log10(AF_range+eps), 'b', 'LineWidth',1.5);
xlabel('Delay (\mus)'); ylabel('Magnitude (dB)');
title('Zero-Doppler Cut (Range Profile)'); grid on;
ylim([-60 5]);

% Measure 3dB range resolution from ambiguity
half_pwr = AF_range >= (1/sqrt(2));
range_3dB_us = (sum(half_pwr) / cfg.fs) * 1e6;
fprintf('   3dB Range Resolution (from AF): %.4f µs (%.2f m)\n', ...
    range_3dB_us, range_3dB_us*1e-6 * cfg.c/2);

%% =========================================================================
%  SECTION 3: ECHO SIGNAL SIMULATION (Multi-target, Swerling models)
% =========================================================================
fprintf('[3/9] Simulating multi-target echo + AWGN + clutter...\n');

N_range = round(cfg.PRI * cfg.fs);   % total range-gate samples
N_pulses = cfg.N_pulses;
rx_matrix = zeros(N_range, N_pulses);  % rows=range, cols=pulses

for pulse_idx = 1:N_pulses
    rx_pulse = zeros(1, N_range);

    for tgt = 1:length(cfg.target_ranges)
        R0  = cfg.target_ranges(tgt);
        vel = cfg.target_vel(tgt);
        rcs = cfg.target_rcs(tgt);

        % Swerling amplitude fluctuation
        amp = swerling_amplitude(rcs, cfg.swerling_model, pulse_idx);

        % Two-way propagation delay
        R_current = R0 + vel * (pulse_idx-1) * cfg.PRI;
        delay_samp = round(2 * R_current / cfg.c * cfg.fs);

        if delay_samp + N_samp - 1 <= N_range
            % Range-Doppler coupling: phase shift per pulse
            phase_doppler = exp(1j * 4*pi * vel * (pulse_idx-1) * cfg.PRI / cfg.lambda);
            echo = amp * tx * phase_doppler;
            rx_pulse(delay_samp : delay_samp+N_samp-1) = ...
                rx_pulse(delay_samp : delay_samp+N_samp-1) + echo;
        end
    end

    % Add AWGN
    noise_power = 10^(-cfg.SNR_dB/10);
    noise = sqrt(noise_power/2) * (randn(1,N_range) + 1j*randn(1,N_range));
    rx_pulse = rx_pulse + noise;

    % Add clutter
    rx_pulse = add_clutter(rx_pulse, cfg.clutter_type, cfg.clutter_power);

    rx_matrix(:, pulse_idx) = rx_pulse.';
end

%% =========================================================================
%  SECTION 4: MATCHED FILTER / PULSE COMPRESSION
% =========================================================================
fprintf('[4/9] Applying matched filter (pulse compression)...\n');

% Matched filter kernel = time-reversed conjugate of tx
mf_kernel = conj(fliplr(tx));
N_mf = length(mf_kernel);

% Apply adaptive window to reduce range sidelobes
win = get_window(N_mf, cfg.window_type);
mf_windowed = mf_kernel .* win;

mf_output = zeros(N_range, N_pulses);
for p = 1:N_pulses
    raw  = rx_matrix(:,p).';
    out  = conv(raw, mf_windowed, 'same');
    mf_output(:,p) = out.';
end

% SNR gain from matched filter (theoretical = TBP)
TBP = cfg.B * cfg.T;
fprintf('   Time-Bandwidth Product (TBP) = %.1f (%.1f dB SNR gain)\n', ...
    TBP, 10*log10(TBP));

%% =========================================================================
%  SECTION 5: CLUTTER MITIGATION
% =========================================================================
fprintf('[5/9] Clutter mitigation: %s...\n', cfg.clutter_filter);

mti_output = apply_clutter_filter(mf_output, cfg.clutter_filter);

%% =========================================================================
%  SECTION 6: DOPPLER / RANGE-DOPPLER MAP (FFT across pulses)
% =========================================================================
fprintf('[6/9] Computing Range-Doppler map...\n');

doppler_win = get_window(N_pulses, 'hamming');
RD_map = zeros(N_range, N_pulses);
for r = 1:N_range
    % Ensure both the signal and the window are column vectors for multiplication
    RD_map(r,:) = fftshift(fft(mti_output(r,:).' .* doppler_win(:), N_pulses));
end

% Axes
range_axis   = (0:N_range-1) * cfg.c / (2*cfg.fs);  % [m]
prf          = 1 / cfg.PRI;
vel_axis     = linspace(-prf/2, prf/2, N_pulses) * cfg.lambda/2; % [m/s]

figure('Name','Range-Doppler Map','NumberTitle','off','Color','k');
imagesc(vel_axis, range_axis/1e3, 20*log10(abs(RD_map)+eps));
xlabel('Radial Velocity (m/s)'); ylabel('Range (km)');
title('Range-Doppler Map (after MTI + Pulse Compression)');
colorbar; axis xy;
caxis([max(20*log10(abs(RD_map(:)+eps)))-50, max(20*log10(abs(RD_map(:)+eps)))]);
colormap jet;

%% =========================================================================
%  SECTION 7: CFAR DETECTION
% =========================================================================
fprintf('[7/9] CFAR Detection: %s-CFAR (Pfa = %.1e)...\n', cfg.cfar_type, cfg.cfar_pfa);

% Use the summed range profile (non-coherent integration across Doppler)
range_profile = sum(abs(RD_map).^2, 2);  % power summed over Doppler
range_profile = range_profile / max(range_profile);

% Apply CFAR
[detections, threshold_vec] = apply_cfar(range_profile, cfg);

% Also compute fixed threshold result for comparison
threshold_fixed = cfg.fixed_threshold * ones(size(range_profile));
detections_fixed = range_profile > threshold_fixed;

fprintf('   Detections (CFAR)  : %d targets\n', sum(detections));
fprintf('   Detections (Fixed) : %d targets\n', sum(detections_fixed));

% Plot detection results
figure('Name','CFAR Detection','NumberTitle','off','Color','k');
subplot(2,1,1);
plot(range_axis/1e3, 20*log10(range_profile+eps), 'b', 'LineWidth',1.2); hold on;
plot(range_axis/1e3, 20*log10(threshold_vec+eps), 'r--', 'LineWidth',1.5);
plot(range_axis(detections)/1e3, 20*log10(range_profile(detections)+eps), ...
     'gv', 'MarkerSize',10, 'LineWidth',2);
xlabel('Range (km)'); ylabel('Power (dB)');
title(sprintf('%s-CFAR Detection | Pfa = %.1e', cfg.cfar_type, cfg.cfar_pfa));
legend('Range Profile','CFAR Threshold','Detections'); grid on;

subplot(2,1,2);
plot(range_axis/1e3, 20*log10(range_profile+eps), 'b', 'LineWidth',1.2); hold on;
plot(range_axis/1e3, 20*log10(threshold_fixed+eps), 'm--', 'LineWidth',1.5);
plot(range_axis(detections_fixed)/1e3, 20*log10(range_profile(detections_fixed)+eps), ...
     'rv', 'MarkerSize',10, 'LineWidth',2);
xlabel('Range (km)'); ylabel('Power (dB)');
title('Fixed Threshold Detection');
legend('Range Profile','Fixed Threshold','Detections'); grid on;

%% =========================================================================
%  SECTION 8: SNR ANALYSIS & Pd-Pfa ROC CURVE
% =========================================================================
fprintf('[8/9] Computing SNR improvement & ROC curve...\n');

% Before/after pulse compression SNR
raw_profile  = sum(abs(rx_matrix).^2, 2);
raw_profile  = raw_profile / max(raw_profile);
mf_profile   = sum(abs(mf_output).^2, 2);
mf_profile   = mf_profile / max(mf_profile);

peak_idx = find(detections, 1, 'first');
if ~isempty(peak_idx)
    snr_before = 10*log10(raw_profile(peak_idx) / mean(raw_profile));
    snr_after  = 10*log10(mf_profile(peak_idx)  / mean(mf_profile));
    fprintf('   SNR before MF: %.2f dB\n', snr_before);
    fprintf('   SNR after  MF: %.2f dB\n', snr_after);
    fprintf('   SNR Gain      : %.2f dB\n', snr_after - snr_before);
end

% ROC Curve — analytical Swerling 0 (Marcum Q)
SNR_lin = 10^(cfg.SNR_dB/10);
pfa_vec = logspace(-6, 0, 200);
pd_ca   = zeros(size(pfa_vec));
for i = 1:length(pfa_vec)
    % CA-CFAR threshold factor alpha given Pfa and N training cells
    N_train = 2 * cfg.cfar_train;
    alpha_cfar = N_train * (pfa_vec(i)^(-1/N_train) - 1);
    % Pd for Swerling-0 (non-fluctuating): Q-Marcum approx
    thresh = alpha_cfar; 
    % approximate Pd using Gaussian approximation of envelope detector
    mu_signal = sqrt(SNR_lin);
    pd_ca(i)  = qfunc((qfuncinv(pfa_vec(i)) - mu_signal));
    pd_ca(i)  = max(0, min(1, pd_ca(i)));
end

figure('Name','ROC Curve','NumberTitle','off','Color','k');
semilogx(pfa_vec, pd_ca, 'b-', 'LineWidth', 2); hold on;
% Mark operating point
semilogx(cfg.cfar_pfa, 0.9, 'r*', 'MarkerSize', 12, 'LineWidth', 2);
xlabel('Probability of False Alarm (Pfa)');
ylabel('Probability of Detection (Pd)');
title(sprintf('ROC Curve — SNR = %d dB, Swerling Model %d', ...
    cfg.SNR_dB, cfg.swerling_model));
legend('CA-CFAR (Analytical)', sprintf('Operating Point (Pfa=%.0e)', cfg.cfar_pfa));
grid on; xlim([1e-6 1]); ylim([0 1]);

%% =========================================================================
%  SECTION 9: SENSITIVITY & PARAMETRIC ANALYSIS
% =========================================================================
fprintf('[9/9] Running parametric sensitivity analysis...\n');

% 9A: SNR sweep — Detection probability vs SNR
snr_sweep  = -5:2:25;
pd_snr_CA  = zeros(size(snr_sweep));
pd_snr_GO  = zeros(size(snr_sweep));

for k = 1:length(snr_sweep)
    pd_snr_CA(k) = simulate_pd(snr_sweep(k), 'CA', cfg);
    pd_snr_GO(k) = simulate_pd(snr_sweep(k), 'GO', cfg);
end

figure('Name','Parametric Analysis','NumberTitle','off','Color','k');
subplot(2,2,1);
plot(snr_sweep, pd_snr_CA, 'b-o', 'LineWidth',1.5, 'MarkerSize',5); hold on;
plot(snr_sweep, pd_snr_GO, 'r-s', 'LineWidth',1.5, 'MarkerSize',5);
xlabel('Input SNR (dB)'); ylabel('Pd');
title('Pd vs SNR for CA-CFAR & GO-CFAR');
legend('CA-CFAR','GO-CFAR'); grid on; ylim([0 1]);

% 9B: Bandwidth vs Range Resolution & PSL
bw_sweep  = [10 20 30 50 75 100] * 1e6;
res_sweep = cfg.c ./ (2 * bw_sweep);
psrr_LFM  = 13.3 * ones(size(bw_sweep)); % -13.3 dB for LFM (theoretical)
psrr_PC   = 20*log10(13) * ones(size(bw_sweep)); % Barker-13

subplot(2,2,2);
yyaxis left
plot(bw_sweep/1e6, res_sweep, 'b-o','LineWidth',1.5,'MarkerSize',6);
ylabel('Range Resolution (m)');
yyaxis right
plot(bw_sweep/1e6, psrr_LFM, 'r--','LineWidth',1.5);
ylabel('PSL (dB)'); xlabel('Bandwidth (MHz)');
title('Bandwidth vs Resolution & PSL');
legend('Resolution','PSL (LFM)','Location','northeast'); grid on;

% 9C: Guard/Training cells vs Pfa (CFAR sensitivity)
guard_sweep = 1:1:8;
pfa_guard   = zeros(size(guard_sweep));
for g = 1:length(guard_sweep)
    cfg_temp = cfg;
    cfg_temp.cfar_guard = guard_sweep(g);
    [~, thr_g] = apply_cfar(range_profile, cfg_temp);
    % estimate empirical Pfa from noise-only region
    noise_region = range_profile(1:100);
    pfa_guard(g) = mean(noise_region > mean(thr_g));
end

subplot(2,2,3);
semilogy(guard_sweep, max(pfa_guard,1e-6), 'g-^', 'LineWidth',1.5,'MarkerSize',6);
xlabel('Guard Cells (each side)'); ylabel('Empirical Pfa');
title('Guard Cell Selection vs Pfa'); grid on;

% 9D: Window type comparison — mainlobe width vs PSL
windows = {'none','hamming','hanning','blackman','chebyshev'};
win_PSL = [-13.3, -42.7, -31.5, -58.1, -60.0];   % dB (typical values)
win_BW  = [0.89,   1.36,  1.44,  1.68,  1.53];    % normalized (× 1/T)

subplot(2,2,4);
bar_data = [win_PSL; win_BW * 10]'; % scale for visibility
b = bar(bar_data);
b(1).FaceColor = [0.2 0.4 0.8];
b(2).FaceColor = [0.8 0.3 0.2];
set(gca,'XTickLabel', windows, 'XTickLabelRotation',15);
ylabel('Value');
title('Window Comparison: PSL (dB) vs 10×Norm. BW');
legend('PSL (dB)','10 × Norm. BW'); grid on;

%% =========================================================================
%  SECTION 10: BEFORE / AFTER PROCESSING COMPARISON
% =========================================================================
fig = figure('Name','Processing Chain Comparison','NumberTitle','off','Color','k'); % Black figure background

% --- Subplot 1: Raw Signal ---
ax1 = subplot(3,1,1);
plot(range_axis/1e3, 20*log10(raw_profile+eps), 'w', 'LineWidth',1.2); % White line for visibility
set(ax1, 'Color', [0.15 0.15 0.15], 'XColor', 'w', 'YColor', 'w', 'GridColor', 'w'); % Dark gray bg
xlabel('Range (km)', 'Color', 'w'); ylabel('Power (dB)', 'Color', 'w');
title('Raw Received Signal (before any processing)', 'Color', 'w'); grid on;

% --- Subplot 2: Matched Filter ---
ax2 = subplot(3,1,2);
plot(range_axis/1e3, 20*log10(mf_profile+eps), 'c', 'LineWidth',1.2); % Cyan line
set(ax2, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'GridColor', 'w'); % Black bg
xlabel('Range (km)', 'Color', 'w'); ylabel('Power (dB)', 'Color', 'w');
title('After Matched Filter (Pulse Compressed)', 'Color', 'w'); grid on;

% --- Subplot 3: MTI + CFAR ---
ax3 = subplot(3,1,3);
mti_profile = sum(abs(mti_output).^2, 2);
mti_profile = mti_profile / max(mti_profile);
plot(range_axis/1e3, 20*log10(mti_profile+eps), 'r', 'LineWidth',1.2); hold on;
plot(range_axis(detections)/1e3, 20*log10(mti_profile(detections)+eps), ...
     'gv', 'MarkerSize',10, 'LineWidth',2);
set(ax3, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'GridColor', 'w'); % Black bg
xlabel('Range (km)', 'Color', 'w'); ylabel('Power (dB)', 'Color', 'w');
title(['After MTI + CFAR Detection (' cfg.cfar_type '-CFAR)'], 'Color', 'w'); grid on;
lgd = legend('Processed Signal','Detections');
set(lgd, 'TextColor', 'w', 'Color', 'none', 'EdgeColor', 'w');

%% =========================================================================
%%                          HELPER FUNCTIONS
%% =========================================================================

% ----- 1. LFM Chirp Waveform -----
function tx = generate_LFM(t, B, T)
    k = B / T;  % chirp rate [Hz/s]
    tx = exp(1j * pi * k .* t.^2);
    tx = tx .* hamming(length(t))';  % mild amplitude taper
end

% ----- 2. Phase-Coded Waveform (Barker codes) -----
function tx = generate_PhaseCode(N_samp, code_type)
    switch code_type
        case 'Barker13'
            code = [1 1 1 1 1 -1 -1 1 1 -1 1 -1 1];
        case 'Barker7'
            code = [1 1 1 -1 -1 1 -1];
        otherwise
            code = [1 1 1 1 1 -1 -1 1 1 -1 1 -1 1];  % default Barker-13
    end
    spc = floor(N_samp / length(code));  % samples per chip
    tx_base = repelem(code, spc);
    tx = zeros(1, N_samp);
    tx(1:length(tx_base)) = tx_base;
    tx = tx .* exp(1j * pi/4);  % BPSK modulation
end

% ----- 3. Hybrid Waveform (LFM + Phase-Coded overlay) -----
function tx = generate_Hybrid(t, B, T, N_samp)
    lfm  = generate_LFM(t, B, T);
    code = generate_PhaseCode(N_samp, 'Barker13');
    len  = min(length(lfm), length(code));
    tx   = lfm(1:len) .* code(1:len);
    tx   = tx / max(abs(tx));
end

% ----- 4. Ambiguity Function -----
function [AF, delay_ax, dop_ax] = compute_ambiguity(tx, fs, lambda)
    N = length(tx);
    N_dop = 64;  % number of Doppler frequency bins
    dop_vec = linspace(-1/(2*lambda), 1/(2*lambda), N_dop);  % m/s -> Hz

    AF = zeros(N_dop, 2*N-1);
    for d = 1:N_dop
        fd = 2 * dop_vec(d) / lambda;  % Doppler frequency shift [Hz]
        t_vec = (0:N-1)/fs;
        tx_shifted = tx .* exp(1j*2*pi*fd*t_vec);
        corr_out = xcorr(tx_shifted, tx);
        AF(d,:) = corr_out;
    end
    AF = AF / max(abs(AF(:)));
    delay_ax  = (-N+1:N-1)/fs;
    dop_ax    = dop_vec;
end

% ----- 5. Window Function -----
function w = get_window(N, win_type)
    switch lower(win_type)
        case 'none'
            w = ones(1,N);
        case 'hamming'
            w = hamming(N)';
        case 'hanning'
            w = hann(N)';
        case 'blackman'
            w = blackman(N)';
        case 'chebyshev'
            w = chebwin(N, 60)';
        otherwise
            w = hamming(N)';
    end
    w = w / max(w);  % normalize
end

% ----- 6. Clutter Generator -----
function rx = add_clutter(rx, clutter_type, clutter_power)
    N = length(rx);
    switch clutter_type
        case 'white'
            c = sqrt(clutter_power/2) * (randn(1,N) + 1j*randn(1,N));
        case 'nonstationary'
            % Low-frequency colored clutter (exponential decay profile)
            envelope = exp(-((1:N)/N)*5) .* (1 + 0.3*sin(2*pi*5*(1:N)/N));
            c = sqrt(clutter_power) * envelope .* ...
                (randn(1,N) + 1j*randn(1,N)) / sqrt(2);
        case 'none'
            c = zeros(1,N);
        otherwise
            c = zeros(1,N);
    end
    rx = rx + c;
end

% ----- 7. Swerling Target RCS Model -----
function amp = swerling_amplitude(rcs_mean, model, pulse_idx)
    switch model
        case 0  % Non-fluctuating (Marcum)
            amp = sqrt(rcs_mean);
        case 1  % Swerling I: Rayleigh, scan-to-scan decorrelation
            amp = sqrt(rcs_mean/2) * abs(randn + 1j*randn);
        case 2  % Swerling II: Rayleigh, pulse-to-pulse decorrelation
            amp = sqrt(rcs_mean/2) * abs(randn + 1j*randn);
        case 3  % Swerling III: Chi-squared 4 DOF, scan-to-scan
            amp = sqrt(rcs_mean/4) * abs(randn + randn*1j + randn + 1j*randn);
        case 4  % Swerling IV: Chi-squared 4 DOF, pulse-to-pulse
            amp = sqrt(rcs_mean/4) * abs(randn + randn*1j + randn + 1j*randn);
        otherwise
            amp = sqrt(rcs_mean);
    end
end

% ----- 8. Clutter Filter (MTI / Adaptive / Doppler) -----
function output = apply_clutter_filter(mf_mat, filter_type)
    [N_range, N_pulses] = size(mf_mat);
    output = mf_mat;

    switch filter_type
        case 'MTI'
            % 2-pulse MTI canceller: y[n] = x[n] - x[n-1]
            for r = 1:N_range
                output(r,:) = filter([1 -1], 1, mf_mat(r,:));
            end
        case 'Doppler'
            % Apply bandpass Doppler filter to suppress zero-velocity clutter
            bpf = fir1(32, [0.05 0.95], 'bandpass');  % normalized cutoffs
            for r = 1:N_range
                output(r,:) = filtfilt(bpf, 1, mf_mat(r,:));
            end
        case 'Adaptive'
            % Least-Mean-Squares (LMS) adaptive clutter canceller
            mu = 0.01;
            M  = 4;   % filter order
            for r = 1:N_range
                w  = zeros(M,1);
                x  = mf_mat(r,:);
                y  = zeros(1, N_pulses);
                for n = M:N_pulses
                    xv     = x(n:-1:n-M+1).';
                    e      = x(n) - w'*xv;
                    w      = w + 2*mu*xv*conj(e);
                    y(n)   = e;
                end
                output(r,:) = y;
            end
        case 'none'
            output = mf_mat;
    end
end

% ----- 9. CFAR Detector -----
function [detections, threshold_vec] = apply_cfar(profile, cfg)
    N   = length(profile);
    G   = cfg.cfar_guard;
    T_c = cfg.cfar_train;
    Pfa = cfg.cfar_pfa;
    N_train = 2 * T_c;

    % Alpha factor for CA-CFAR (from Pfa)
    alpha_CA = N_train * (Pfa^(-1/N_train) - 1);

    detections    = false(N,1);
    threshold_vec = zeros(N,1);

    for i = T_c+G+1 : N-T_c-G
        % Leading and lagging windows
        lag_win  = profile(i-T_c-G : i-G-1);
        lead_win = profile(i+G+1   : i+T_c+G);

        switch upper(cfg.cfar_type)
            case 'CA'  % Cell-Averaging
                noise_est = mean([lag_win; lead_win]);
                alpha     = alpha_CA;
            case 'GO'  % Greatest-Of
                noise_est = max(mean(lag_win), mean(lead_win));
                alpha     = alpha_CA;
            case 'OS'  % Ordered-Statistic (k = 3/4 * N)
                combined  = sort([lag_win; lead_win], 'ascend');
                k_os      = round(0.75 * length(combined));
                noise_est = combined(k_os);
                alpha     = alpha_CA;
            case 'FIXED'
                noise_est = 1;
                alpha     = cfg.fixed_threshold;
            otherwise
                noise_est = mean([lag_win; lead_win]);
                alpha     = alpha_CA;
        end

        threshold_vec(i) = alpha * noise_est;
        if profile(i) > threshold_vec(i)
            detections(i) = true;
        end
    end

    % Fill edges with max threshold to avoid false alarms
    edge_thresh = max(threshold_vec);
    threshold_vec(1:T_c+G) = edge_thresh;
    threshold_vec(N-T_c-G+1:end) = edge_thresh;
end

% ----- 10. Monte-Carlo Pd Estimator -----
function pd = simulate_pd(snr_dB, cfar_type, cfg)
    N_mc  = 200;
    N_rng = 256;
    hits  = 0;
    snr_lin = 10^(snr_dB/10);

    cfg_mc = cfg;
    cfg_mc.cfar_type  = cfar_type;
    cfg_mc.cfar_guard = 2;
    cfg_mc.cfar_train = 8;

    for mc = 1:N_mc
        noise = (randn(1,N_rng) + 1j*randn(1,N_rng)) / sqrt(2);
        sig_amp = sqrt(snr_lin);
        tgt_loc = 100;  % fixed target at bin 100
        noise(tgt_loc) = noise(tgt_loc) + sig_amp;
        profile = abs(noise).^2;
        profile = profile / max(profile);

        [dets, ~] = apply_cfar(profile.', cfg_mc);
        if dets(tgt_loc)
            hits = hits + 1;
        end
    end
    pd = hits / N_mc;
end

% ----- 11. Q-function helpers -----
function y = qfunc(x)
    y = 0.5 * erfc(x / sqrt(2));
end
function x = qfuncinv(p)
    x = sqrt(2) * erfcinv(2*p);
end