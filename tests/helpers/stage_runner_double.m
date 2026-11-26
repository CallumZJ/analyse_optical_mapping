classdef stage_runner_double < rabbit_reconstruction_tab
    %STAGE_RUNNER_DOUBLE Controllable external-stage double.
    % Test-only subclass: exercises the real run_stage/run_pipeline orchestration
    % while replacing only external process execution and tool preflight.

    properties (Access = public)
        execution_mode = 'exit130';
        gui_app = [];
        observed_run_dir = '';
        observed_status_during_spawn = '';
        observed_results_during_spawn = {};
        observed_status_after_second = '';
        observed_results_after_second = {};
        callback_count = 0;
        cancel_request_count = 0;
        fail_set_status = false;
        fail_record_run = false;
        fail_confirmation = false;
        observed_cancel_exists_during_spawn = false;
    end

    methods (Access = public)
        function [ok, results] = preflight(~, varargin)
            ok = true;
            results = struct('name', 'test_double', 'ok', true, ...
                'message', 'Test-only controllable executor.');
        end

        function [cmd, meta] = build_stage_command(~, stage, ~, ~)
            cmd = sprintf('c32-test-double %s', stage);
            meta = struct();
            meta.kind = 'external';
            meta.timeout_s = 1;
            meta.settings_resolved = struct('test_double', true);
            meta.licence = 'test-only';
            meta.citation_key = '';
            meta.citations = {};
        end

        function [ok, err, exit_code, spawned] = spawn_and_wait(obj, ~, ~, cancel_file, ~, ~, stage)
            spawned = {};
            obj.observed_cancel_exists_during_spawn = exist(cancel_file, 'file') == 2;
            if strcmp(obj.execution_mode, 'success')
                exit_code = 0;
                ok = true;
                err = '';
                return;
            end
            if strcmp(obj.execution_mode, 'callback_exit130')
                obj.callback_count = obj.callback_count + 1;
                obj.gui_app.recon.ReconstructionCancelButtonPushed();
                run_dir = obj.observed_run_dir;
                m = obj.read_manifest(run_dir);
                if isstruct(m) && isfield(m, 'result') && isfield(m.result, 'status')
                    obj.observed_status_during_spawn = char(m.result.status);
                end
                obj.observed_results_during_spawn = obj.gui_app.recon.ReconstructionResultsText.Value;
                % A repeated GUI click must be idempotent: the callback sees
                % pending ownership and must not request cancellation again.
                obj.gui_app.recon.ReconstructionCancelButtonPushed();
                m2 = obj.read_manifest(run_dir);
                if isstruct(m2) && isfield(m2, 'result') && isfield(m2.result, 'status')
                    obj.observed_status_after_second = char(m2.result.status);
                end
                obj.observed_results_after_second = obj.gui_app.recon.ReconstructionResultsText.Value;
                exit_code = 130;
                ok = false;
                err = sprintf('%s was cancelled. %s', obj.stage_label(stage), obj.unconfirmed_stop_note());
                return;
            end
            if strcmp(obj.execution_mode, 'timeout124')
                exit_code = 124;
                ok = false;
                err = sprintf('%s took longer than its time limit and was stopped. %s', ...
                    obj.stage_label(stage), obj.unconfirmed_stop_note());
                return;
            end
            if strcmp(obj.execution_mode, 'exit1')
                exit_code = 1;
                ok = false;
                err = sprintf('%s stopped with exit code 1.', obj.stage_label(stage));
                return;
            end
            exit_code = 130;
            ok = false;
            err = sprintf('%s was cancelled. %s', obj.stage_label(stage), obj.unconfirmed_stop_note());
        end

        function [ok, err, checks, warnings, artifacts] = validate_stage(obj, stage, run_dir, opts)
            if strcmp(obj.execution_mode, 'success')
                ok = true;
                err = '';
                checks = struct('name', 'test-double', 'result', true);
                warnings = {};
                artifacts = {};
                return;
            end
            [ok, err, checks, warnings, artifacts] = validate_stage@rabbit_reconstruction_tab(obj, stage, run_dir, opts);
        end

        function [ok, err] = request_cancel(obj, run_id)
            obj.cancel_request_count = obj.cancel_request_count + 1;
            [ok, err] = request_cancel@rabbit_reconstruction_tab(obj, run_id);
        end

        function [ok, err] = set_run_status(obj, run_id, status)
            if obj.fail_set_status
                ok = false;
                err = 'INJECTED manifest status write failure';
                return;
            end
            [ok, err] = set_run_status@rabbit_reconstruction_tab(obj, run_id, status);
        end

        function [ok, err] = record_run(obj, run_id, status)
            if obj.fail_record_run
                ok = false;
                err = 'INJECTED tab-state write failure';
                return;
            end
            [ok, err] = record_run@rabbit_reconstruction_tab(obj, run_id, status);
        end

        function [ok, err] = confirm_run_status(obj, run_id, status)
            if obj.fail_confirmation
                ok = false;
                err = 'INJECTED canonical read-back failure';
                return;
            end
            [ok, err] = confirm_run_status@rabbit_reconstruction_tab(obj, run_id, status);
        end
    end
end
