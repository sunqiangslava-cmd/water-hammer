%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 塑料管道粘弹性参数全自动识别与验证平台（数据接入版）
% 功能：支持从 CSV/Excel 读取多工况频域数据，供后续识别/验证流程直接使用
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear; clc; close all;
rng(123);

%% ====================== 1. 全局参数设置 ======================
L = 100;
D = 0.05;
e = 0.005;
a = 1200;
nu_p = 0.46;
rho = 1000;
g = 9.81;
nu = 1e-6;

psi = D/(D+e) + 2*e/D*(1+2*nu_p);
fprintf('文档公式自动计算轴向约束系数 ψ = %.4f\n', psi);

%% ====================== 2. 数据输入模式 ======================
% mode = "synthetic"：生成模拟数据
% mode = "file"：从 CSV/Excel 读取真实实验数据
mode = "file";

% 文件模式下：
% 支持 .csv/.xlsx/.xls
% 必需列：case_id, f_hz, h, Q0
% 可选列：h_true
% 每行是一条频点记录；同一个 case_id 会聚合成一个工况
input_file = "data/experiment_cases.csv";

switch mode
    case "synthetic"
        true_J = [2e-10, 6e-11];
        true_tau = [0.01, 0.1];
        Q0_list = [0.0008, 0.001, 0.0012];
        noise_level = 0.02;

        f_common = linspace(0.1, 50, 500);
        cases = cell(1, length(Q0_list));

        for i = 1:length(Q0_list)
            Q0 = Q0_list(i);
            omega = 2*pi*f_common;
            h_true = calculate_frequency_response(true_J, true_tau, L, D, e, a, psi, rho, g, nu, Q0, omega);
            h_meas = h_true + noise_level * std(h_true) * randn(size(h_true));

            cases{i}.f = f_common;
            cases{i}.h = h_meas;
            cases{i}.Q0 = Q0;
            cases{i}.h_true = h_true;
        end

    case "file"
        cases = load_multi_case_data(input_file);

    otherwise
        error('未知 mode：%s（可选 synthetic/file）', mode);
end

fprintf('\n读取到 %d 个工况\n', length(cases));
for i = 1:length(cases)
    Re0 = 4*cases{i}.Q0/(pi*D*nu);
    fprintf('工况%d：频点=%d, Q0=%.6f m^3/s, Re0=%.0f\n', i, length(cases{i}.f), cases{i}.Q0, Re0);
end

%% ====================== 3. 后续识别流程接入点 ======================
% 你现有的 multi_stage_kv_identification / bayesopt 识别逻辑可直接复用：
% [J_best, tau_best, best_n] = multi_stage_kv_identification(...);
% 或
% results = bayesopt(...);

fprintf('\n数据加载完成。你可以将 cases 直接传入现有识别主流程。\n');

%% ====================== 核心函数 ======================
function cases = load_multi_case_data(file_path)
% 从 CSV/Excel 读取多工况频域数据
% 必需列：case_id, f_hz, h, Q0

    if ~isfile(file_path)
        error('数据文件不存在：%s', file_path);
    end

    [~,~,ext] = fileparts(file_path);
    ext = lower(ext);

    switch ext
        case '.csv'
            T = readtable(file_path, 'VariableNamingRule', 'preserve');
        case {'.xlsx', '.xls'}
            T = readtable(file_path, 'VariableNamingRule', 'preserve');
        otherwise
            error('不支持的文件类型：%s（仅支持 csv/xlsx/xls）', ext);
    end

    required_cols = {'case_id','f_hz','h','Q0'};
    missing = required_cols(~ismember(required_cols, T.Properties.VariableNames));
    if ~isempty(missing)
        error('缺少必需列：%s', strjoin(missing, ', '));
    end

    % 清理无效行
    valid = ~isnan(T.f_hz) & ~isnan(T.h) & ~isnan(T.Q0);
    T = T(valid,:);

    case_ids = unique(T.case_id, 'stable');
    cases = cell(1, numel(case_ids));

    has_h_true = ismember('h_true', T.Properties.VariableNames);

    for i = 1:numel(case_ids)
        mask = isequaln_vectorized(T.case_id, case_ids(i));
        Ti = T(mask, :);

        [f_sorted, order] = sort(Ti.f_hz);
        h_sorted = Ti.h(order);
        q0_vec = Ti.Q0(order);

        if any(abs(q0_vec - q0_vec(1)) > 0)
            error('case_id=%s 存在多个 Q0，请保证同一工况的 Q0 一致', to_text(case_ids(i)));
        end

        cases{i}.f = f_sorted(:)';
        cases{i}.h = h_sorted(:)';
        cases{i}.Q0 = q0_vec(1);

        if has_h_true
            h_true_sorted = Ti.h_true(order);
            cases{i}.h_true = h_true_sorted(:)';
        end
    end
end

function mask = isequaln_vectorized(col, value)
% 兼容 cellstr/string/double/categorical 的逐元素比较
    if iscell(col)
        mask = cellfun(@(x) isequaln(x, value), col);
    else
        mask = arrayfun(@(x) isequaln(x, value), col);
    end
end

function s = to_text(v)
% 统一转字符串用于报错信息
    if isstring(v) || ischar(v)
        s = char(v);
    elseif isnumeric(v)
        s = num2str(v);
    elseif iscategorical(v)
        s = char(string(v));
    else
        s = '<unknown>';
    end
end

function h_amp = calculate_frequency_response(J, tau, L, D, e, a, psi, rho, g, nu, Q0, omega_vec)
% 简化版：用于 synthetic 模式生成演示数据
    A = pi * D^2 / 4;
    Re0 = 4 * Q0 / (pi * D * nu);
    f = 0.3164 / Re0^0.25;
    R = f * Q0 / (g * D * A^2);

    h_amp = zeros(size(omega_vec));
    for idx = 1:length(omega_vec)
        omega = omega_vec(idx);

        sum_ve = 0;
        for k = 1:length(J)
            sum_ve = sum_ve + J(k) / (1 + 1i * omega * tau(k));
        end
        T_VE = 1 + (rho * a^2 * D * psi / e) * sum_ve;

        term_mu = 1 + g * A * R / (1i * omega);
        mu = (1i * omega / a) * sqrt(T_VE * term_mu);
        Z = (a / (g * A)) * sqrt(term_mu / T_VE);

        F11 = cosh(mu * L);
        F21 = -Z * sinh(mu * L);
        q_u = 1 / F11;
        h_d = F21 * q_u;
        h_amp(idx) = abs(h_d);
    end
end
