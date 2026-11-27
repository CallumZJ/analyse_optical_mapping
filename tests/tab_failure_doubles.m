classdef tab_failure_doubles < rabbit_reconstruction_tab
    %TAB_FAILURE_DOUBLES Probe-side double that injects failures for the restore probes.
    %Contract: C1.2 s6.0/s16.6 - the `fail_on` cell-string property selects the
    %seam whose failure tuple is returned; every other call passes through to
    %the superclass. Arity per the s16.6 table.
    %
    %Scope: probe-side ONLY (never shipped); the production class is untouched.

    properties (Access = public)
        fail_on = {};
    end

    methods (Access = public)
        function obj = tab_failure_doubles(varargin)
            %TAB_FAILURE_DOUBLES Constructor: optional ('fail_on', {names}) pair.
            %The base class is a no-op constructor, so no superclass call is
            %needed (MATLAB supplies the implicit one).
            for k = 1:2:numel(varargin)
                if strcmp(varargin{k}, 'fail_on') && k < numel(varargin)
                    obj.fail_on = varargin{k + 1};
                end
            end
        end

        function [ok, err] = write_manifest_v2_sidecar(obj, run_dir, v2bytes)
            if any(strcmp(obj.fail_on, 'write_manifest_v2_sidecar'))
                ok = false;
                err = 'analyse_om:Reconstruction:TestInjected:write_manifest_v2_sidecar';
                return;
            end
            [ok, err] = write_manifest_v2_sidecar@rabbit_reconstruction_tab(obj, run_dir, v2bytes);
        end

        function [ok, err] = commit_state_candidate(obj, cand)
            if any(strcmp(obj.fail_on, 'commit_state_candidate'))
                ok = false;
                err = 'analyse_om:Reconstruction:TestInjected:commit_state_candidate';
                return;
            end
            [ok, err] = commit_state_candidate@rabbit_reconstruction_tab(obj, cand);
        end

        function [cand, err] = load_state_candidate(obj, dataset_root, dataset_stem)
            if any(strcmp(obj.fail_on, 'load_state_candidate'))
                cand = struct();
                err = 'analyse_om:Reconstruction:TestInjected:load_state_candidate';
                return;
            end
            [cand, err] = load_state_candidate@rabbit_reconstruction_tab(obj, dataset_root, dataset_stem);
        end

        function [ok, err, result] = write_active_manifest(obj, run_dir, mutate_fcn)
            if any(strcmp(obj.fail_on, 'write_active_manifest'))
                ok = false;
                err = 'analyse_om:Reconstruction:TestInjected:write_active_manifest';
                result = [];
                return;
            end
            [ok, err, result] = write_active_manifest@rabbit_reconstruction_tab(obj, run_dir, mutate_fcn);
        end
    end
end
