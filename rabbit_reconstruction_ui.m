classdef rabbit_reconstruction_ui < handle
    %% Reconstruction/Reprojection tab of analyse_optical_mapping
    % Collin Snitchler
    % 23.11.2026
    %
    % Purpose
    %   The tab's controls, its two File menus (Open Reconstruction
    %   Manifest, Reconstruction Help), its state and its callbacks. They
    %   are built in code, not in analyse_optical_mapping.mlapp, so that an
    %   App Designer save cannot remove them; the app makes this object in
    %   startupFcn:
    %     app.recon = rabbit_reconstruction_ui(app, app.TabGroup, app.FileMenu);
    %   The work itself (runs, manifests, tools) is done by
    %   rabbit_reconstruction_tab; this class is the window side of it.
    %   Run, Resume and Reproject are synchronous: their callback calls
    %   run_pipeline and returns when the run ends, which can take hours.
    %   Cancel reaches the run only while an outside program is being
    %   waited for (spawn_and_wait calls drawnow; the progress dialog's
    %   timer checks its Cancel button); a MATLAB stage (run_matlab_stage)
    %   is not interrupted and finishes first.
    %
    % Section map (search for the quoted line; line numbers move)
    %   Constructor and layout  "function obj = rabbit_reconstruction_ui("
    %     Step panels ......... "% ---- StepPanel1 ----" to "% ---- StepPanel4 ----"
    %     Edit tools .......... "% ---- ToolsPanel (copy-on-write tools) ----"
    %     Steps and Results ... "% ---- Steps panel (centre) ----", "% ---- Results panel (right) ----"
    %   Open manifest ......... "function OpenReconstructionManifestMenuSelected"
    %   Run, cancel, resume ... "function ReconstructionRunButtonPushed"
    %   Visualise ............. "function ReconstructionVisualiseButtonPushed"
    %   Point and mesh edits .. "function reconstruction_edit_refresh(obj)"
    %   Gate state ............ "% ---- gate state + accordion helpers (private)"
    %   Steps panel ........... "function total = steps_rowtotal"
    %   Details ............... "function reconstruction_show_details(obj)"
    %   Recording rhythm ...... "function reconstruction_rhythm_refresh(obj)"
    %   Sparse model build .... "% ---- Step 2: build the sparse model ----"
    %   Rig calibration ....... "function ReconstructionCalibrateButtonPushed"
    %   Help .................. "% ---- Context resolver"
    %   Help preferences ...... "% ---- Preference adapter"
    %   Help window ........... "% ---- Help lifecycle"
    %   Menu callbacks ........ "% ---- Menu/button callbacks"
    %
    % Contract with the app (obj.host):
    %   Reads:
    %     CV_method - the Conduction Velocity tab's method, for the CV map
    %     FileMenu - the File menu the two menus are added to
    %     data - the loaded recording's frame rate and calibration/cut fields
    %     data.rhythm - the recording's rhythm marker (rabbit_recording_rhythm):
    %       Step 2's Pacing cycle shows its cycle, and each projection records
    %       it (recording_rhythm)
    %     display - which normalisation of the image stack is shown (display.normalisation)
    %     distancemax - the Conduction Velocity tab's maximum distance, for the CV map
    %     figure_size - the window size at start-up, for the tab group's height when a manifest is opened
    %     file_info - the loaded recording's folder and name (dataset folder, stem, file pickers)
    %     focus_main_window - brings the main window to the front after a dialog
    %     opticalmappingUIFigure - the main window: parent of the tab's alerts, questions and progress windows
    %     processed_data - the activation map and image stacks that reprojection maps onto the mesh
    %     timemax - the Conduction Velocity tab's maximum time, for the CV map
    %   Writes:
    %     TabGroup - the tab group: its height and selected tab change with the tab (Open manifest, Help, tab height)
    %     history_field - the History tab: a line per run, reprojection and opened manifest
    %     data.rhythm - through rabbit_recording_rhythm (from_step2, ask_once), when
    %       Step 2's Pacing cycle is typed or the question is answered before a
    %       projection: the same value as File > Recording rhythm
    %     processed_data.scale, data.calibration_scale - through rabbit_calibration_scale,
    %       when a calibration made in the calibration window fills the
    %       Conduction Velocity tab's scale
    %     timemax, TimemaxmsEditFieldLabel - through rabbit_cv_map.controls:
    %       the time window's two-frame default while it is not typed, and
    %       the Smooth activation times checkbox made on the CV tab
    %   Reads once, in the constructor, to put the tab and the menus in
    %   their places among the app's own: LoadfilepartiallyMenu, HelpMenu, HistoryTab.
    %   The constructor also adds File > Current app screenshot
    %   (app_screenshot.attach_menu, after the Workspace menu).
    %   app_screenshot (File > Current app screenshot) raises and lowers
    %   ReconstructionHelpProgrammaticSelectionDepth while it chooses each
    %   tab, and puts back ReconstructionHelpFreshShownThisSelection
    %   afterwards, so that no Help window opens.
    %   Sets TabGroup.SelectionChangedFcn (contextual Help when the tab is
    %   chosen) and listens for the app's deletion to close the Help window.
    %   Passes the app itself to these functions, which read the members
    %   above (and app_display_limits the Activation Map and Conduction
    %   Velocity tabs' Y limits); rabbit_rhythm_reproject reads this tab's
    %   controls as app.recon.<name>:
    %     rabbit_rhythm_reproject.app_display_limits,
    %     rabbit_rhythm_reproject.om_image_from_app,
    %     rabbit_rhythm_reproject.run_from_app,
    %     rabbit_segmentation_masks.write_for_run.
    %   rabbit_calibration_scale calls ReconstructionCalibrateButtonPushed
    %   (with a function to call after the calibration) and reads
    %   reconstruction_has_dataset, reconstruction_calibration_root,
    %   ReconstructionCalibrationDropDown, ReconstructionImagesField and
    %   ReconstructionRoiField.
    %   The app calls these methods of this class:
    %     bind_reconstruction_tab_for_test,
    %     reconstruction_assert_no_active_run, reconstruction_edit_refresh,
    %     reconstruction_edit_reset_state, reconstruction_fill_from_cut,
    %     reconstruction_maybe_show_first_run, reconstruction_refresh,
    %     reconstruction_rhythm_refresh (through rabbit_recording_rhythm.mark).
    %   and sets or reads these properties (startupFcn, close request):
    %     ReconstructionHelpStartupComplete, reconstruction_help_figure.
    %   The app's figure_size is public so that this class can read it.

    properties (Access = public)
        host % The app this tab belongs to (analyse_optical_mapping)
        OpenReconstructionManifestMenu  matlab.ui.container.Menu
        ReconstructionTab                matlab.ui.container.Tab
        ReconstructionRunButton         matlab.ui.control.Button
        ReconstructionResumeButton       matlab.ui.control.Button
        ReconstructionCancelButton      matlab.ui.control.Button
        ReconstructionRefreshButton     matlab.ui.control.Button
        ReconstructionRunList           matlab.ui.control.ListBox
        ReconstructionCitationsButton   matlab.ui.control.Button
        ReconstructionStageList         matlab.ui.control.ListBox
        StageRowsGrid                   matlab.ui.container.GridLayout
        ReconstructionDatasetFolderLabel matlab.ui.control.Label
        ReconstructionDatasetFolderDropDown matlab.ui.control.DropDown
        ReconstructionLogViewer         matlab.ui.control.TextArea
        ReconstructionShowLogCheckBox   matlab.ui.control.CheckBox
        StepWarningsText                matlab.ui.control.TextArea
        ReconstructionAttemptLabel      matlab.ui.control.Label
        ReconstructionAttemptDropDown   matlab.ui.control.DropDown
        ReconstructionLogFolderButton   matlab.ui.control.Button
        ReconstructionResultsText       matlab.ui.control.TextArea
        ReconstructionWhyButton         matlab.ui.control.Button
        ReconstructionDetailsButton     matlab.ui.control.Button
        ReconstructionDatasetField      matlab.ui.control.EditField
        ReconstructionSparseField        matlab.ui.control.EditField
        ReconstructionSparseButton      matlab.ui.control.Button
        ReconstructionSparseSourceDropDown matlab.ui.control.DropDown
        ReconstructionSfmRecipeDropDown matlab.ui.control.DropDown
        ReconstructionSfmDetailsButton  matlab.ui.control.Button
        ReconstructionCalibrationLabel  matlab.ui.control.Label
        ReconstructionCalibrationDropDown matlab.ui.control.DropDown
        ReconstructionCalibrateButton   matlab.ui.control.Button
        ReconstructionPycamsetGuiButton matlab.ui.control.Button
        ReconstructionCamsetField       matlab.ui.control.EditField
        ReconstructionCamsetButton      matlab.ui.control.Button
        ReconstructionImagesLabel       matlab.ui.control.Label
        ReconstructionImagesField       matlab.ui.control.EditField
        ReconstructionImagesButton     matlab.ui.control.Button
        ReconstructionRoiLabel         matlab.ui.control.Label
        ReconstructionRoiField         matlab.ui.control.EditField
        ReconstructionRoiButton        matlab.ui.control.Button
        ReconstructionViewNumberingLabel matlab.ui.control.Label
        ReconstructionLogLabel         matlab.ui.control.Label
        ReconstructionViewNumberingDropDown matlab.ui.control.DropDown
        ReconstructionOmPoseFrameLabel matlab.ui.control.Label
        ReconstructionOmPoseFrameDropDown matlab.ui.control.DropDown
        ReconstructionReprojectButton  matlab.ui.control.Button
        ReconstructionReprojectFilesButton matlab.ui.control.Button
        ReconstructionMeshMethodLabel  matlab.ui.control.Label
        ReconstructionMeshMethodDropDown matlab.ui.control.DropDown
        ReconstructionCloudSourceLabel matlab.ui.control.Label
        ReconstructionCloudSourceDropDown matlab.ui.control.DropDown
        ReconstructionDenseLabel       matlab.ui.control.Label
        ReconstructionDenseDropDown    matlab.ui.control.DropDown
        ReconstructionEdgeWeightLabel  matlab.ui.control.Label
        ReconstructionEdgeWeightField  matlab.ui.control.NumericEditField
        ReconstructionPacingCycleLabel matlab.ui.control.Label
        ReconstructionPacingCycleField matlab.ui.control.EditField
        ReconstructionVisualiseButton  matlab.ui.control.Button
        ReconstructionOpenRunFolderButton matlab.ui.control.Button
        VisualiseFusedLabel           matlab.ui.control.Label
        VisualiseFusedField           matlab.ui.control.EditField
        VisualiseRebuiltLabel         matlab.ui.control.Label
        VisualiseRebuiltField         matlab.ui.control.EditField
        VisualiseProjectedLabel       matlab.ui.control.Label
        VisualiseProjectedField       matlab.ui.control.EditField
        VisualiseStatusText           matlab.ui.control.TextArea
        TouchupSectionLabel          matlab.ui.control.Label
        TouchupSourceField           matlab.ui.control.EditField
        TouchupOpDropDown            matlab.ui.control.DropDown
        TouchupBoxField              matlab.ui.control.EditField
        TouchupMinFacesField         matlab.ui.control.NumericEditField
        TouchupPreviewButton         matlab.ui.control.Button
        TouchupApplyButton           matlab.ui.control.Button
        TouchupResetButton           matlab.ui.control.Button
        TouchupOutputField           matlab.ui.control.EditField
        TouchupStatusText            matlab.ui.control.TextArea
        IntensitySectionLabel        matlab.ui.control.Label
        IntensitySourceField         matlab.ui.control.EditField
        IntensityModeDropDown        matlab.ui.control.DropDown
        IntensityThresholdField      matlab.ui.control.NumericEditField
        IntensityPreviewButton       matlab.ui.control.Button
        IntensityApplyButton         matlab.ui.control.Button
        IntensityResetButton         matlab.ui.control.Button
        IntensityOutputField         matlab.ui.control.EditField
        IntensityStatusText         matlab.ui.control.TextArea
        AreaSectionLabel            matlab.ui.control.Label
        AreaSourceField             matlab.ui.control.EditField
        AreaShapeDropDown           matlab.ui.control.DropDown
        AreaSelectButton            matlab.ui.control.Button
        AreaPreviewButton           matlab.ui.control.Button
        AreaApplyButton             matlab.ui.control.Button
        AreaResetButton             matlab.ui.control.Button
        AreaOutputField             matlab.ui.control.EditField
        AreaStatusText              matlab.ui.control.TextArea
        SmoothSectionLabel          matlab.ui.control.Label
        SmoothSourceField           matlab.ui.control.EditField
        SmoothRadiusField           matlab.ui.control.NumericEditField
        SmoothIterationsField       matlab.ui.control.NumericEditField
        SmoothStrengthField         matlab.ui.control.NumericEditField
        SmoothSelectButton          matlab.ui.control.Button
        SmoothPreviewButton         matlab.ui.control.Button
        SmoothApplyButton           matlab.ui.control.Button
        SmoothResetButton           matlab.ui.control.Button
        SmoothOutputField           matlab.ui.control.EditField
        SmoothStatusText            matlab.ui.control.TextArea
        ReconstructionColmapField        matlab.ui.control.EditField
        ReconstructionApdField           matlab.ui.control.EditField
        ReconstructionRunPyField         matlab.ui.control.EditField
        ReconstructionPythonField        matlab.ui.control.EditField
        ReconstructionModelsField        matlab.ui.control.EditField
        ReconstructionModelsLabel        matlab.ui.control.Label
        ReconstructionColmapBrowseButton matlab.ui.control.Button
        ReconstructionApdBrowseButton    matlab.ui.control.Button
        ReconstructionRunPyBrowseButton  matlab.ui.control.Button
        ReconstructionPythonBrowseButton matlab.ui.control.Button
        ReconstructionModelsBrowseButton matlab.ui.control.Button
        ReconstructionDatasetLabel       matlab.ui.control.Label
        ReconstructionSparseLabel        matlab.ui.control.Label
        ReconstructionColmapLabel        matlab.ui.control.Label
        ReconstructionApdLabel           matlab.ui.control.Label
        ReconstructionRunPyLabel         matlab.ui.control.Label
        ReconstructionPythonLabel        matlab.ui.control.Label
        ReconstructionRunListLabel       matlab.ui.control.Label
        GridLayoutR                      matlab.ui.container.GridLayout
        GridLayoutR1                     matlab.ui.container.GridLayout
        GridLayoutR2                     matlab.ui.container.GridLayout
        GridLayoutR3                     matlab.ui.container.GridLayout
        RunControlPanel                  matlab.ui.container.Panel
        StagePipelinePanel               matlab.ui.container.Panel
        ResultsPanel                     matlab.ui.container.Panel
        % ---- Session state (not controls): in memory for this app session; these properties are not saved ----
        reconstruction_restore_mode          logical = false
        % The activation map record of the opened run, checked by
        % open_manifest; Visualise draws from it.
        activation_restore_state = struct()
        % The calibration window, while it is open
        reconstruction_calibration_window = []
        % The run the restored activation state was opened from
        activation_restore_run_id = ''
        % Transient UI state. Neither field is written to manifests
        % or tab-state; durable status changes only after backend read-back.
        cancel_pending_run_id = ''
        unconfirmed_run_id = ''
        % The four tool paths at the last Check tools, and its outcome
        % ('' = not checked, 'OK' or the first failure)
        reconstruction_tools_checked_paths = ''
        reconstruction_tools_check_result = ''
        % Step 3 tool paths: typed = paths the user typed or
        % browsed to in this app session, per tool; shown = what the app
        % last put in each field, so a typed change can be told apart;
        % note = which saved dataset paths no longer exist and were passed
        % over (shown in the step 3 header until Check tools)
        reconstruction_tool_memory = struct('typed', struct(), 'shown', struct(), 'note', '')
        % Step 2 "Build sparse model": the SfM recipe file chosen with
        % "Custom recipe file..." ('' = the default recipe)
        reconstruction_sfm_recipe_file = ''
        % The dense clouds chosen for a new run, per sparse model source
        % (the defaults: COLMAP for a built model, both on a supplied one)
        reconstruction_dense_by_source = struct('built', 'colmap', 'supplied', 'both')
        % Completion check per run for the run list, kept while the run
        % record does not change: struct of run_id, stamp, clean
        reconstruction_consistency_cache = struct('run_id', {}, 'stamp', {}, 'clean', {})
        % The shared panel owns pending preview tokens and
        % last-applied identities; source artefacts remain external.
        CopyOnWriteState = struct('status', 'No run selected')
        CopyOnWritePending = struct('operation', {}, 'run_id', {}, ...
            'source_path', {}, 'source_sha256', {}, 'parameters', {}, ...
            'preview_info', {}, ...
            'parameters_sha256', {}, 'view_identity', {}, ...
            'manifest_sha256', {}, 'output_snapshot', {}, 'valid', {})
        CopyOnWriteApplied = struct('operation', {}, 'run_id', {}, ...
            'selected_run_id', {}, 'output_path', {}, 'output_sha256', {}, 'manifest_path', {}, ...
            'record_id', {}, 'source_sha256', {})
        % ---- Controls (continued) ----
        JourneyStripPanel matlab.ui.container.Panel
        GridLayoutJ matlab.ui.container.GridLayout
        JourneyStripLabel matlab.ui.control.Label
        StepPanel1 matlab.ui.container.Panel
        StepPanel1Layout matlab.ui.container.GridLayout
        StepHeader1 matlab.ui.control.Button
        StepPanel2 matlab.ui.container.Panel
        StepPanel2Layout matlab.ui.container.GridLayout
        StepHeader2 matlab.ui.control.Button
        StepPanel3 matlab.ui.container.Panel
        StepPanel3Layout matlab.ui.container.GridLayout
        StepHeader3 matlab.ui.control.Button
        StepPanel4 matlab.ui.container.Panel
        StepPanel4Layout matlab.ui.container.GridLayout
        StepHeader4 matlab.ui.control.Button
        GridLayoutS1 matlab.ui.container.GridLayout
        GridLayoutS2 matlab.ui.container.GridLayout
        GridLayoutS3 matlab.ui.container.GridLayout
        GridLayoutS4 matlab.ui.container.GridLayout
        Step2StatusChip matlab.ui.control.Label
        ReconstructionCheckToolsButton matlab.ui.control.Button
        ReconstructionRunListEmptyLabel matlab.ui.control.Label
        ToolsPanel matlab.ui.container.Panel
        ToolsPanelLayout matlab.ui.container.GridLayout
        ToolsHeader matlab.ui.control.Button
        GridLayoutS5 matlab.ui.container.GridLayout
        CopyOnWritePanel matlab.ui.container.GridLayout
        CopyOnWriteContractLabel matlab.ui.control.Label
        CopyOnWriteSummaryLabel matlab.ui.control.Label
        CopyOnWriteStatusLabel matlab.ui.control.Label
        TouchupPanel matlab.ui.container.Panel
        GridLayoutT1 matlab.ui.container.GridLayout
        TouchupComposeLabel matlab.ui.control.Label
        IntensityPanel matlab.ui.container.Panel
        GridLayoutT2 matlab.ui.container.GridLayout
        IntensityComposeLabel matlab.ui.control.Label
        AreaPanel matlab.ui.container.Panel
        GridLayoutT3 matlab.ui.container.GridLayout
        AreaComposeLabel matlab.ui.control.Label
        SmoothPanel matlab.ui.container.Panel
        GridLayoutT4 matlab.ui.container.GridLayout
        SmoothComposeLabel matlab.ui.control.Label
        ReconstructionHelpMenu          matlab.ui.container.Menu
        ReconstructionGuideButton       matlab.ui.control.Button
    end

    % Test access: set or read only by the tests in tests/ (headless runs);
    % the app leaves them at their defaults
    properties (Access = public, Hidden)
        % Visualise: '' = normal; a non-empty error id forces the failure path
        % (probe_restore_and_visualise_gui)
        test_visualise_fails = ''
        % Visualise: a successful visualiser that opens no figure (probe_restore_gui_safety)
        test_visualise_empty = false
        % The last validated result of Open Reconstruction Manifest (probe_manifest_moved_run_anomaly)
        last_open_info = struct()
        % Open Reconstruction Manifest: a manifest path used instead of the file picker
        % (probe_restore_gui_safety, probe_run_status and the other restore probes)
        test_manifest_pick = ''
        % Point edits: fixture mode and its failure switches, set by
        % tests/helpers/reconstruction_ui_fixture.m (probe_point_edit_tool_panel)
        test_edit_fixture_mode = false
        test_edit_fixture_manifest_fail = false
        test_edit_fixture_noop = false
    end

    properties (Access = public, Transient)
        % Help-window transient state (read by the tests).
        reconstruction_help_figure = [];           % uifigure handle or []
        ReconstructionHelpProgrammaticSelectionDepth uint32 = uint32(0);
        ReconstructionHelpFreshShownThisSelection logical = false;
        ReconstructionHelpStartupComplete logical = false;
        reconstruction_help_topic_list = [];
        reconstruction_help_show_again_checkbox = [];
        reconstruction_help_pref_adapter_store = []; % Test injection point for the help window
        reconstruction_help_citation_adapter_store = []; % read-only test hook
    end

    properties (Access = private)
        reconstruction_tab; % The backend (rabbit_reconstruction_tab) of the bound dataset; [] when none is bound.
                            % Made anew by reconstruction_refresh (each dataset bind) and by
                            % OpenReconstructionManifestMenuSelected; swapped by bind_reconstruction_tab_for_test.
                            % Do not keep a reference to it across those calls.
        AreaSelection; % 2D screen-area removal: the active operation (shape/rect|poly/camera/source_ply)
        AreaFigure; % 2D screen-area removal: the selection-view figure handle
        SmoothSelection; % Bounded circular smoothing: the active operation (center/radius_px/iterations/strength/camera/axpos/source_ply)
        SmoothFigure; % Bounded circular smoothing: the selection-view figure handle
        StageRowButtons = {} % one button per step in the Steps list
        StageRowChips = {} % the state chip of each step in the Steps list
    end

    methods (Access = public)

        function obj = rabbit_reconstruction_ui(host, tab_group, file_menu)
            % Make the tab in tab_group and the two menus in file_menu
            % (the app's TabGroup and FileMenu)
            obj.host = host;

            % Create OpenReconstructionManifestMenu (open a
            % saved reconstruction run manifest and resume from that
            % saved run without starting from scratch).
            obj.OpenReconstructionManifestMenu = uimenu(file_menu);
            obj.OpenReconstructionManifestMenu.MenuSelectedFcn = @(src, event) obj.OpenReconstructionManifestMenuSelected(event);
            obj.OpenReconstructionManifestMenu.Tooltip = {'Open a saved reconstruction run (manifest.json) and carry on from where it stopped. The saved files are checked first and are never changed.'};
            obj.OpenReconstructionManifestMenu.Text = 'Open Reconstruction Manifest';

            % Create ReconstructionHelpMenu (next to Help)
            obj.ReconstructionHelpMenu = uimenu(file_menu);
            obj.ReconstructionHelpMenu.MenuSelectedFcn = @(src, event) obj.ReconstructionHelpMenuSelected(event);
            obj.ReconstructionHelpMenu.Tooltip = {'Open the guide to the Reconstruction/Reprojection tab. Opening it does not change any run.'};
            obj.ReconstructionHelpMenu.Text = 'Reconstruction Help';

            % Contextual help auto-open (guarded against programmatic selection).
            tab_group.SelectionChangedFcn = @(src, event) obj.TabGroupSelectionChanged(event);

            % Create ReconstructionTab (guided workflow)
            % Method citations: COLMAP (Schoenberger & Frahm 2016, CVPR;
            % Schoenberger et al. 2016, ECCV); APDe-MVS (Zeng et al. 2025, Pattern
            % Recognition); RHYTHM (Gloschat et al. 2018, Sci Rep 8:2921, PMID 29440763).
            obj.ReconstructionTab = uitab(tab_group);
            obj.ReconstructionTab.Title = 'Reconstruction/Reprojection';

            % Create GridLayoutR (journey strip + 3 panels)
            obj.GridLayoutR = uigridlayout(obj.ReconstructionTab);
            obj.GridLayoutR.ColumnWidth = {'1x', '0.9x', '1.2x'};   % the Results rows are 78 characters
            obj.GridLayoutR.RowHeight = {30, '1x'};

            % ---- Journey strip (always visible) ----
            obj.JourneyStripPanel = uipanel(obj.GridLayoutR);
            obj.JourneyStripPanel.BorderType = 'none';
            obj.JourneyStripPanel.Layout.Row = 1;
            obj.JourneyStripPanel.Layout.Column = [1 3];
            obj.GridLayoutJ = uigridlayout(obj.JourneyStripPanel);
            obj.GridLayoutJ.ColumnWidth = {'1x', 80};
            obj.GridLayoutJ.RowHeight = [26];
            obj.GridLayoutJ.Padding = [0 2 0 2];
            obj.JourneyStripLabel = uilabel(obj.GridLayoutJ);
            obj.JourneyStripLabel.Text = 'New run | 1 Load data | 2 Inputs | 3 Tools | 4 Run';
            obj.JourneyStripLabel.Layout.Row = 1;
            obj.JourneyStripLabel.Layout.Column = 1;

            % Create ReconstructionGuideButton
            obj.ReconstructionGuideButton = uibutton(obj.GridLayoutJ, 'push');
            obj.ReconstructionGuideButton.Text = 'Guide';
            obj.ReconstructionGuideButton.Tooltip = {'Open help for the current reconstruction step or selected run.'};
            obj.ReconstructionGuideButton.Layout.Row = 1;
            obj.ReconstructionGuideButton.Layout.Column = 2;
            obj.ReconstructionGuideButton.ButtonPushedFcn = @(src, event) obj.ReconstructionGuideButtonPushed(event);

            % ---- Run control panel (left) ----
            obj.RunControlPanel = uipanel(obj.GridLayoutR);
            obj.RunControlPanel.Title = 'Run control';
            obj.RunControlPanel.Layout.Row = 2;
            obj.RunControlPanel.Layout.Column = 1;
            obj.RunControlPanel.FontWeight = 'bold';

            % Create GridLayoutR1 (accordion: 5 rows)
            obj.GridLayoutR1 = uigridlayout(obj.RunControlPanel);
            obj.GridLayoutR1.ColumnWidth = {'1x'};
            obj.GridLayoutR1.RowHeight = repmat(58,1,5);
            obj.GridLayoutR1.RowSpacing = 6;
            obj.GridLayoutR1.Padding = [6 6 6 6];
            obj.GridLayoutR1.Scrollable = 'on';

            % ---- StepPanel1 ----
            obj.StepPanel1 = uipanel(obj.GridLayoutR1);
            obj.StepPanel1.Title = '';
            obj.StepPanel1.BorderType = 'none';
            obj.StepPanel1.Layout.Row = 1;
            obj.StepPanel1.Layout.Column = 1;
            obj.StepPanel1Layout = uigridlayout(obj.StepPanel1);
            obj.StepPanel1Layout.ColumnWidth = {'1x'};
            obj.StepPanel1Layout.RowHeight = {58, '1x'};
            obj.StepPanel1Layout.Padding = [0 0 0 0];
            obj.StepPanel1Layout.RowSpacing = 4;
            obj.StepHeader1 = uibutton(obj.StepPanel1Layout, 'push');
            obj.StepHeader1.ButtonPushedFcn = @(src, ev) reconstruction_on_step_header_toggled(obj, src, ev);
            obj.StepHeader1.Text = '1. Load optical mapping data';
            obj.StepHeader1.WordWrap = 'on';
            obj.StepHeader1.Layout.Row = 1;
            obj.StepHeader1.Layout.Column = 1;
            obj.GridLayoutS1 = uigridlayout(obj.StepPanel1Layout);
            obj.GridLayoutS1.ColumnWidth = {'1x', '2x'};
            obj.GridLayoutS1.RowHeight = [22 22];
            obj.GridLayoutS1.Layout.Row = 2;
            obj.GridLayoutS1.Layout.Column = 1;

            obj.ReconstructionDatasetField = uieditfield(obj.GridLayoutS1, 'text');
            obj.ReconstructionDatasetField.Editable = 'off';
            obj.ReconstructionDatasetField.Tooltip = {'The optical mapping recording this reconstruction belongs to. It is set when a file is loaded.'};
            obj.ReconstructionDatasetField.Layout.Row = 1;
            obj.ReconstructionDatasetField.Layout.Column = 2;

            obj.ReconstructionDatasetLabel = uilabel(obj.GridLayoutS1);
            obj.ReconstructionDatasetLabel.Text = 'Dataset';
            obj.ReconstructionDatasetLabel.Layout.Row = 1;
            obj.ReconstructionDatasetLabel.Layout.Column = 1;

            % A recording that has runs can have further dataset folders,
            % <stem>_01.matom and so on
            obj.ReconstructionDatasetFolderLabel = uilabel(obj.GridLayoutS1);
            obj.ReconstructionDatasetFolderLabel.Text = 'Dataset folder';
            obj.ReconstructionDatasetFolderLabel.Layout.Row = 2;
            obj.ReconstructionDatasetFolderLabel.Layout.Column = 1;

            obj.ReconstructionDatasetFolderDropDown = uidropdown(obj.GridLayoutS1);
            obj.ReconstructionDatasetFolderDropDown.Items = {'-'};
            obj.ReconstructionDatasetFolderDropDown.Enable = 'off';
            obj.ReconstructionDatasetFolderDropDown.Tooltip = {'Where the runs of this recording are kept. Choose an existing folder to see its runs, or start a new one. No run is changed or moved.'};
            obj.ReconstructionDatasetFolderDropDown.ValueChangedFcn = @(src, ev) reconstruction_dataset_folder_changed(obj);
            obj.ReconstructionDatasetFolderDropDown.Layout.Row = 2;
            obj.ReconstructionDatasetFolderDropDown.Layout.Column = 2;

            % ---- StepPanel2 ----
            obj.StepPanel2 = uipanel(obj.GridLayoutR1);
            obj.StepPanel2.Title = '';
            obj.StepPanel2.BorderType = 'none';
            obj.StepPanel2.Layout.Row = 2;
            obj.StepPanel2.Layout.Column = 1;
            obj.StepPanel2Layout = uigridlayout(obj.StepPanel2);
            obj.StepPanel2Layout.ColumnWidth = {'1x'};
            obj.StepPanel2Layout.RowHeight = {58, '1x'};
            obj.StepPanel2Layout.Padding = [0 0 0 0];
            obj.StepPanel2Layout.RowSpacing = 4;
            obj.StepHeader2 = uibutton(obj.StepPanel2Layout, 'push');
            obj.StepHeader2.ButtonPushedFcn = @(src, ev) reconstruction_on_step_header_toggled(obj, src, ev);
            obj.StepHeader2.Text = '2. Supply reconstruction inputs';
            obj.StepHeader2.WordWrap = 'on';
            obj.StepHeader2.Layout.Row = 1;
            obj.StepHeader2.Layout.Column = 1;
            obj.GridLayoutS2 = uigridlayout(obj.StepPanel2Layout);
            obj.GridLayoutS2.ColumnWidth = {'2x', '1x'};
            obj.GridLayoutS2.RowHeight = [22 22 22 22 22 22 22 22 22 22 22 22 22];
            obj.GridLayoutS2.Layout.Row = 2;
            obj.GridLayoutS2.Layout.Column = 1;

            obj.ReconstructionSparseLabel = uilabel(obj.GridLayoutS2);
            obj.ReconstructionSparseLabel.Text = 'Sparse model';
            obj.ReconstructionSparseLabel.Layout.Row = 1;
            obj.ReconstructionSparseLabel.Layout.Column = 1;

            obj.ReconstructionSparseButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionSparseButton.Text = 'Browse...';
            obj.ReconstructionSparseButton.ButtonPushedFcn = @(src, event) obj.ReconstructionSparseButtonPushed(event);
            obj.ReconstructionSparseButton.Tooltip = {'Choose the COLMAP sparse model folder (cameras, images and points files).'};
            obj.ReconstructionSparseButton.Layout.Row = 2;
            obj.ReconstructionSparseButton.Layout.Column = 2;

            obj.ReconstructionSparseField = uieditfield(obj.GridLayoutS2, 'text');
            obj.ReconstructionSparseField.Tooltip = {'COLMAP sparse model folder: the camera poses for the reconstruction images.'};
            obj.ReconstructionSparseField.Layout.Row = 2;
            obj.ReconstructionSparseField.Layout.Column = 1;

            % Build the sparse model from the cut images (COLMAP), or use
            % an existing one. Row 2 shows the recipe and its
            % details when building, the folder and Browse otherwise.
            obj.ReconstructionSparseSourceDropDown = uidropdown(obj.GridLayoutS2);
            obj.ReconstructionSparseSourceDropDown.Items = {'Build from images (COLMAP)', 'Use an existing sparse model'};
            obj.ReconstructionSparseSourceDropDown.ItemsData = {'built', 'supplied'};
            obj.ReconstructionSparseSourceDropDown.Value = 'built';
            obj.ReconstructionSparseSourceDropDown.ValueChangedFcn = @(src, ev) reconstruction_sparse_source_changed(obj);
            obj.ReconstructionSparseSourceDropDown.Tooltip = {'Build the sparse model (camera poses) from the cut reconstruction images with COLMAP, or use a sparse model made before.'};
            obj.ReconstructionSparseSourceDropDown.Layout.Row = 1;
            obj.ReconstructionSparseSourceDropDown.Layout.Column = 2;

            obj.ReconstructionSfmRecipeDropDown = uidropdown(obj.GridLayoutS2);
            obj.ReconstructionSfmRecipeDropDown.Items = {'Rabbit 4-view (default)', 'Custom recipe file...'};
            obj.ReconstructionSfmRecipeDropDown.ItemsData = {'rabbit_4view_v1', 'custom'};
            obj.ReconstructionSfmRecipeDropDown.Value = 'rabbit_4view_v1';
            obj.ReconstructionSfmRecipeDropDown.ValueChangedFcn = @(src, ev) ReconstructionSfmRecipeDropDownValueChanged(obj);
            obj.ReconstructionSfmRecipeDropDown.Tooltip = {'Settings used to build the sparse model. Details... shows them and the COLMAP commands.'};
            obj.ReconstructionSfmRecipeDropDown.Layout.Row = 2;
            obj.ReconstructionSfmRecipeDropDown.Layout.Column = 1;
            obj.ReconstructionSfmRecipeDropDown.Visible = 'off';

            obj.ReconstructionSfmDetailsButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionSfmDetailsButton.Text = 'Details...';
            obj.ReconstructionSfmDetailsButton.ButtonPushedFcn = @(src, ev) ReconstructionSfmDetailsButtonPushed(obj);
            obj.ReconstructionSfmDetailsButton.Tooltip = {'Show the settings and COLMAP commands of the sparse model recipe, and save a copy to edit.'};
            obj.ReconstructionSfmDetailsButton.Layout.Row = 2;
            obj.ReconstructionSfmDetailsButton.Layout.Column = 2;
            obj.ReconstructionSfmDetailsButton.Visible = 'off';

            obj.ReconstructionImagesLabel = uilabel(obj.GridLayoutS2);
            obj.ReconstructionImagesLabel.Text = 'Reconstruction images';
            obj.ReconstructionImagesLabel.Layout.Row = 3;
            obj.ReconstructionImagesLabel.Layout.Column = 1;

            obj.ReconstructionImagesButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionImagesButton.Text = 'Browse...';
            obj.ReconstructionImagesButton.ButtonPushedFcn = @(src, event) obj.ReconstructionImagesButtonPushed(event);
            obj.ReconstructionImagesButton.Tooltip = {'Choose the folder of reconstruction images (TIFF) named in the sparse model.'};
            obj.ReconstructionImagesButton.Layout.Row = 4;
            obj.ReconstructionImagesButton.Layout.Column = 2;

            obj.ReconstructionImagesField = uieditfield(obj.GridLayoutS2, 'text');
            obj.ReconstructionImagesField.Tooltip = {'Folder of reconstruction images (TIFF). Filled in by the cut after Define regions.'};
            obj.ReconstructionImagesField.Layout.Row = 4;
            obj.ReconstructionImagesField.Layout.Column = 1;
            obj.ReconstructionImagesField.ValueChangedFcn = @(src, ev) reconstruction_path_typed(obj);

            obj.ReconstructionRoiLabel = uilabel(obj.GridLayoutS2);
            obj.ReconstructionRoiLabel.Text = 'Regions file (written by the cut)';
            obj.ReconstructionRoiLabel.Layout.Row = 5;
            obj.ReconstructionRoiLabel.Layout.Column = 1;

            obj.ReconstructionRoiButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionRoiButton.Text = 'Browse...';
            obj.ReconstructionRoiButton.ButtonPushedFcn = @(src, event) obj.ReconstructionRoiButtonPushed(event);
            obj.ReconstructionRoiButton.Tooltip = {'Another regions file (JSON): the cut writes one, regions_<recording>.json next to the cut folders; the region editor''s Save ROI JSON... button writes one too.'};
            obj.ReconstructionRoiButton.Layout.Row = 6;
            obj.ReconstructionRoiButton.Layout.Column = 2;

            obj.ReconstructionRoiField = uieditfield(obj.GridLayoutS2, 'text');
            obj.ReconstructionRoiField.Tooltip = {'Where each view sits on the optical mapping image. Written and filled in by the cut after Define regions.'};
            obj.ReconstructionRoiField.Layout.Row = 6;
            obj.ReconstructionRoiField.Layout.Column = 1;
            obj.ReconstructionRoiField.ValueChangedFcn = @(src, ev) reconstruction_path_typed(obj);

            obj.ReconstructionViewNumberingLabel = uilabel(obj.GridLayoutS2);
            obj.ReconstructionViewNumberingLabel.Text = 'View numbering (which camera is which view)';
            obj.ReconstructionViewNumberingLabel.Layout.Row = 7;
            obj.ReconstructionViewNumberingLabel.Layout.Column = 1;

            obj.ReconstructionViewNumberingDropDown = uidropdown(obj.GridLayoutS2);
            obj.ReconstructionViewNumberingDropDown.Items = {'Automatic', 'Order in the regions file', 'View folder names'};
            obj.ReconstructionViewNumberingDropDown.ItemsData = {'auto', 'roi_rows', 'view_names'};
            obj.ReconstructionViewNumberingDropDown.Value = 'auto';
            obj.ReconstructionViewNumberingDropDown.Tooltip = {'How the view number in the image names maps to the views of the regions file.'; 'Automatic: decided from how the images were made (default).'; 'Order in the regions file: view k is the k-th region, as when the images were cut by this app.'; 'View folder names: folder view<k> is the view called view<k>.'};
            obj.ReconstructionViewNumberingDropDown.Layout.Row = 7;
            obj.ReconstructionViewNumberingDropDown.Layout.Column = 2;

            % OM pose frame: which frame of the
            % reconstruction recording shows the heart as the OM recording
            % does; Automatic, or a frame number typed in
            obj.ReconstructionOmPoseFrameLabel = uilabel(obj.GridLayoutS2);
            % Short, the explanation in the tooltip (a long label is cut)
            obj.ReconstructionOmPoseFrameLabel.Text = 'OM pose frame';
            obj.ReconstructionOmPoseFrameLabel.Tooltip = {'The frame of the reconstruction recording that shows the heart where the OM recording shows it.'};
            obj.ReconstructionOmPoseFrameLabel.Layout.Row = 8;
            obj.ReconstructionOmPoseFrameLabel.Layout.Column = 1;
            obj.ReconstructionOmPoseFrameDropDown = uidropdown(obj.GridLayoutS2);
            obj.ReconstructionOmPoseFrameDropDown.Items = {'Automatic'};
            obj.ReconstructionOmPoseFrameDropDown.Editable = 'on';
            obj.ReconstructionOmPoseFrameDropDown.Value = 'Automatic';
            obj.ReconstructionOmPoseFrameDropDown.Tooltip = {'Which frame''s cameras project the OM views.'; 'Automatic: the earliest of the frames whose heart outline matches the OM views best (default); the projection check names other frames that match as well.'; 'A frame number (type it in): that frame, e.g. when the lab notes say where the OM was recorded.'};
            obj.ReconstructionOmPoseFrameDropDown.Layout.Row = 8;
            obj.ReconstructionOmPoseFrameDropDown.Layout.Column = 2;
            obj.ReconstructionOmPoseFrameDropDown.ValueChangedFcn = @(src, ev) reconstruction_om_pose_frame_changed(obj);

            % Rig calibration (pyCamSet): which calibration a
            % built sparse model takes its scale in mm from
            obj.ReconstructionCalibrationLabel = uilabel(obj.GridLayoutS2);
            obj.ReconstructionCalibrationLabel.Text = 'Calibration (gives mm)';
            obj.ReconstructionCalibrationLabel.Layout.Row = 9;
            obj.ReconstructionCalibrationLabel.Layout.Column = 1;
            obj.ReconstructionCalibrationDropDown = uidropdown(obj.GridLayoutS2);
            obj.ReconstructionCalibrationDropDown.Items = {'None (model units)'};
            obj.ReconstructionCalibrationDropDown.ItemsData = {''};
            obj.ReconstructionCalibrationDropDown.Value = '';
            obj.ReconstructionCalibrationDropDown.ValueChangedFcn = @(src, ev) reconstruction_calibration_changed(obj);
            obj.ReconstructionCalibrationDropDown.Tooltip = {['Calibrations of this recording that may give mm (a FAILED one is not listed). ' ...
                '(PASSED): every check passed, held-out distance checks included. (WARNED): no check failed, but a ' ...
                'held-out distance check could not be made, so the scale''s uncertainty is not estimated. ' ...
                'With None the run works as before, in model units.']};
            obj.ReconstructionCalibrationDropDown.Layout.Row = 9;
            obj.ReconstructionCalibrationDropDown.Layout.Column = 2;
            obj.ReconstructionCalibrateButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionCalibrateButton.Text = 'Calibrate...';
            obj.ReconstructionCalibrateButton.ButtonPushedFcn = @(src, ev) ReconstructionCalibrateButtonPushed(obj, []);
            obj.ReconstructionCalibrateButton.Tooltip = {'Solve the rig in mm with pyCamSet from recordings of a calibration cube.'};
            obj.ReconstructionCalibrateButton.Layout.Row = 10;
            obj.ReconstructionCalibrateButton.Layout.Column = 2;
            % The pyCamSet GUI on a calibration's recording, and
            % a camera set made there, linked as a calibration
            obj.ReconstructionPycamsetGuiButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionPycamsetGuiButton.Text = 'Open in pyCamSet...';
            obj.ReconstructionPycamsetGuiButton.ButtonPushedFcn = @(src, ev) ReconstructionPycamsetGuiButtonPushed(obj);
            obj.ReconstructionPycamsetGuiButton.Tooltip = {['Open the pyCamSet GUI (development branch) at Phase 1 on the ' ...
                'views of the chosen calibration''s recording, to go through the phases yourself.']};
            obj.ReconstructionPycamsetGuiButton.Layout.Row = 10;
            obj.ReconstructionPycamsetGuiButton.Layout.Column = 1;
            obj.ReconstructionCamsetField = uieditfield(obj.GridLayoutS2, 'text');
            obj.ReconstructionCamsetField.Editable = 'off';
            obj.ReconstructionCamsetField.Placeholder = 'pyCamSet camera set (.camset): none linked';
            obj.ReconstructionCamsetField.Tooltip = {['A camera set exported from the pyCamSet GUI. Linking it checks it ' ...
                'on the calibration recordings and adds it to Calibration (gives mm).']};
            obj.ReconstructionCamsetField.Layout.Row = 11;
            obj.ReconstructionCamsetField.Layout.Column = 1;
            obj.ReconstructionCamsetButton = uibutton(obj.GridLayoutS2, 'push');
            obj.ReconstructionCamsetButton.Text = 'Link camera set...';
            obj.ReconstructionCamsetButton.ButtonPushedFcn = @(src, ev) ReconstructionCamsetButtonPushed(obj);
            obj.ReconstructionCamsetButton.Tooltip = {'Choose a .camset made in the pyCamSet GUI.'};
            obj.ReconstructionCamsetButton.Layout.Row = 11;
            obj.ReconstructionCamsetButton.Layout.Column = 2;

            % Pacing cycle: optional, in ms; recorded
            % with the run and with each projection, and named in the
            % Results activation spread caution. Blank: not known.
            % The same value as File > Recording rhythm (the recording's
            % rhythm marker): the field shows the marker's cycle, typing
            % here changes the marker (reconstruction_rhythm_refresh,
            % rabbit_recording_rhythm.from_step2).
            obj.ReconstructionPacingCycleLabel = uilabel(obj.GridLayoutS2);
            obj.ReconstructionPacingCycleLabel.Text = 'Pacing cycle (ms, optional)';
            obj.ReconstructionPacingCycleLabel.Layout.Row = 12;
            obj.ReconstructionPacingCycleLabel.Layout.Column = 1;
            obj.ReconstructionPacingCycleField = uieditfield(obj.GridLayoutS2, 'text');
            obj.ReconstructionPacingCycleField.Value = '';
            obj.ReconstructionPacingCycleField.Placeholder = 'not known';
            obj.ReconstructionPacingCycleField.Tooltip = {['The pacing cycle length of the recording in ms, if known ' ...
                '(2 Hz = 500 ms). Blank: not known. The same value as File > Recording rhythm: a number typed ' ...
                'here marks the recording Paced. Recorded with the run and with each projection (also Redo ' ...
                'projection); Results names it in the activation spread caution.']};
            obj.ReconstructionPacingCycleField.Layout.Row = 12;
            obj.ReconstructionPacingCycleField.Layout.Column = 2;
            obj.ReconstructionPacingCycleField.ValueChangedFcn = @(src, ev) reconstruction_pacing_cycle_changed(obj, ev);

            obj.Step2StatusChip = uilabel(obj.GridLayoutS2);
            obj.Step2StatusChip.Text = 'Not supplied';
            obj.Step2StatusChip.Layout.Row = 13;
            obj.Step2StatusChip.Layout.Column = [1 2];

            % ---- StepPanel3 ----
            obj.StepPanel3 = uipanel(obj.GridLayoutR1);
            obj.StepPanel3.Title = '';
            obj.StepPanel3.BorderType = 'none';
            obj.StepPanel3.Layout.Row = 3;
            obj.StepPanel3.Layout.Column = 1;
            obj.StepPanel3Layout = uigridlayout(obj.StepPanel3);
            obj.StepPanel3Layout.ColumnWidth = {'1x'};
            obj.StepPanel3Layout.RowHeight = {58, '1x'};
            obj.StepPanel3Layout.Padding = [0 0 0 0];
            obj.StepPanel3Layout.RowSpacing = 4;
            obj.StepHeader3 = uibutton(obj.StepPanel3Layout, 'push');
            obj.StepHeader3.ButtonPushedFcn = @(src, ev) reconstruction_on_step_header_toggled(obj, src, ev);
            obj.StepHeader3.Text = '3. Check the tools';
            obj.StepHeader3.WordWrap = 'on';
            obj.StepHeader3.Layout.Row = 1;
            obj.StepHeader3.Layout.Column = 1;
            obj.GridLayoutS3 = uigridlayout(obj.StepPanel3Layout);
            obj.GridLayoutS3.ColumnWidth = {'1x', '2x', 70};
            obj.GridLayoutS3.RowHeight = [22 22 22 22 22 22 22];
            obj.GridLayoutS3.Layout.Row = 2;
            obj.GridLayoutS3.Layout.Column = 1;

            obj.ReconstructionColmapField = uieditfield(obj.GridLayoutS3, 'text');
            obj.ReconstructionColmapField.ValueChangedFcn = @(src, event) obj.ReconstructionToolPathChanged(event);
            obj.ReconstructionColmapField.Tooltip = {'Path to the COLMAP program (colmap.exe).'};
            obj.ReconstructionColmapField.Layout.Row = 1;
            obj.ReconstructionColmapField.Layout.Column = 2;

            obj.ReconstructionColmapLabel = uilabel(obj.GridLayoutS3);
            obj.ReconstructionColmapLabel.Text = 'COLMAP exe';
            obj.ReconstructionColmapLabel.Layout.Row = 1;
            obj.ReconstructionColmapLabel.Layout.Column = 1;

            obj.ReconstructionApdField = uieditfield(obj.GridLayoutS3, 'text');
            obj.ReconstructionApdField.ValueChangedFcn = @(src, event) obj.ReconstructionToolPathChanged(event);
            obj.ReconstructionApdField.Tooltip = {'Path to the APDe-MVS program (APD.exe).'};
            obj.ReconstructionApdField.Layout.Row = 2;
            obj.ReconstructionApdField.Layout.Column = 2;

            obj.ReconstructionApdLabel = uilabel(obj.GridLayoutS3);
            obj.ReconstructionApdLabel.Text = 'APD.exe';
            obj.ReconstructionApdLabel.Layout.Row = 2;
            obj.ReconstructionApdLabel.Layout.Column = 1;

            obj.ReconstructionRunPyField = uieditfield(obj.GridLayoutS3, 'text');
            obj.ReconstructionRunPyField.ValueChangedFcn = @(src, event) obj.ReconstructionToolPathChanged(event);
            obj.ReconstructionRunPyField.Tooltip = {'Path to the APDe-MVS run.py script.'};
            obj.ReconstructionRunPyField.Layout.Row = 3;
            obj.ReconstructionRunPyField.Layout.Column = 2;

            obj.ReconstructionRunPyLabel = uilabel(obj.GridLayoutS3);
            obj.ReconstructionRunPyLabel.Text = 'APDe-MVS run.py';
            obj.ReconstructionRunPyLabel.Layout.Row = 3;
            obj.ReconstructionRunPyLabel.Layout.Column = 1;

            obj.ReconstructionPythonField = uieditfield(obj.GridLayoutS3, 'text');
            obj.ReconstructionPythonField.ValueChangedFcn = @(src, event) obj.ReconstructionToolPathChanged(event);
            obj.ReconstructionPythonField.Tooltip = {'Python environment (folder or python.exe) used to run the APDe-MVS script.'};
            obj.ReconstructionPythonField.Layout.Row = 4;
            obj.ReconstructionPythonField.Layout.Column = 2;
            obj.ReconstructionPythonLabel = uilabel(obj.GridLayoutS3);
            obj.ReconstructionPythonLabel.Text = 'Python env';
            obj.ReconstructionPythonLabel.Layout.Row = 4;
            obj.ReconstructionPythonLabel.Layout.Column = 1;

            % Optional folder of local COLMAP model files (ONNX) for SfM
            % recipes that use ALIKED or LightGlue
            obj.ReconstructionModelsField = uieditfield(obj.GridLayoutS3, 'text');
            obj.ReconstructionModelsField.ValueChangedFcn = @(src, event) obj.ReconstructionToolPathChanged(event);
            obj.ReconstructionModelsField.Tooltip = {'Optional: folder of COLMAP model files (ONNX) for sparse model recipes that use ALIKED or LightGlue. Leave empty for SIFT recipes.'};
            obj.ReconstructionModelsField.Layout.Row = 5;
            obj.ReconstructionModelsField.Layout.Column = 2;
            obj.ReconstructionModelsLabel = uilabel(obj.GridLayoutS3);
            obj.ReconstructionModelsLabel.Text = 'COLMAP models (optional)';
            obj.ReconstructionModelsLabel.Layout.Row = 5;
            obj.ReconstructionModelsLabel.Layout.Column = 1;

            % Browse... for each tool path. The last used paths are kept in
            % the MATLAB preferences of this computer
            obj.ReconstructionColmapBrowseButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionColmapBrowseButton.Text = 'Browse...';
            obj.ReconstructionColmapBrowseButton.ButtonPushedFcn = @(src, ev) reconstruction_browse_tool(obj, 'colmap_exe');
            obj.ReconstructionColmapBrowseButton.Tooltip = {'Choose the COLMAP program (colmap.exe).'};
            obj.ReconstructionColmapBrowseButton.Layout.Row = 1;
            obj.ReconstructionColmapBrowseButton.Layout.Column = 3;
            obj.ReconstructionApdBrowseButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionApdBrowseButton.Text = 'Browse...';
            obj.ReconstructionApdBrowseButton.ButtonPushedFcn = @(src, ev) reconstruction_browse_tool(obj, 'apd_exe');
            obj.ReconstructionApdBrowseButton.Tooltip = {'Choose the APDe-MVS program (APD.exe).'};
            obj.ReconstructionApdBrowseButton.Layout.Row = 2;
            obj.ReconstructionApdBrowseButton.Layout.Column = 3;
            obj.ReconstructionRunPyBrowseButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionRunPyBrowseButton.Text = 'Browse...';
            obj.ReconstructionRunPyBrowseButton.ButtonPushedFcn = @(src, ev) reconstruction_browse_tool(obj, 'apde_run_py');
            obj.ReconstructionRunPyBrowseButton.Tooltip = {'Choose the APDe-MVS run.py script.'};
            obj.ReconstructionRunPyBrowseButton.Layout.Row = 3;
            obj.ReconstructionRunPyBrowseButton.Layout.Column = 3;
            obj.ReconstructionPythonBrowseButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionPythonBrowseButton.Text = 'Browse...';
            obj.ReconstructionPythonBrowseButton.ButtonPushedFcn = @(src, ev) reconstruction_browse_tool(obj, 'apde_python_env');
            obj.ReconstructionPythonBrowseButton.Tooltip = {'Choose the Python interpreter (python.exe) of the APDe-MVS environment.'};
            obj.ReconstructionPythonBrowseButton.Layout.Row = 4;
            obj.ReconstructionPythonBrowseButton.Layout.Column = 3;
            obj.ReconstructionModelsBrowseButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionModelsBrowseButton.Text = 'Browse...';
            obj.ReconstructionModelsBrowseButton.ButtonPushedFcn = @(src, ev) reconstruction_browse_tool(obj, 'colmap_models_dir');
            obj.ReconstructionModelsBrowseButton.Tooltip = {'Choose the folder of COLMAP model files (ONNX).'};
            obj.ReconstructionModelsBrowseButton.Layout.Row = 5;
            obj.ReconstructionModelsBrowseButton.Layout.Column = 3;

            obj.ReconstructionCitationsButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionCitationsButton.Text = 'Citations...';
            obj.ReconstructionCitationsButton.ButtonPushedFcn = @(src, event) obj.ReconstructionCitationsButtonPushed(event);
            obj.ReconstructionCitationsButton.Layout.Row = 7;
            obj.ReconstructionCitationsButton.Layout.Column = [1 3];

            obj.ReconstructionCheckToolsButton = uibutton(obj.GridLayoutS3, 'push');
            obj.ReconstructionCheckToolsButton.ButtonPushedFcn = @(src, ev) reconstruction_check_tools(obj);
            obj.ReconstructionCheckToolsButton.Text = 'Check tools';
            obj.ReconstructionCheckToolsButton.Layout.Row = 6;
            obj.ReconstructionCheckToolsButton.Layout.Column = [1 3];

            % ---- StepPanel4 ----
            % Mesh options, Run / Resume / Cancel / Refresh, the run list,
            % Reproject and Visualise. Method citations: COLMAP
            % (Schonberger & Frahm 2016; Schonberger et al. 2016), APDe-MVS
            % (Zeng et al. 2025), RHYTHM (Gloschat et al. 2018, Sci Rep
            % 8:2921; lineage Laughner et al. 2012).
            obj.StepPanel4 = uipanel(obj.GridLayoutR1);
            obj.StepPanel4.Title = '';
            obj.StepPanel4.BorderType = 'none';
            obj.StepPanel4.Layout.Row = 4;
            obj.StepPanel4.Layout.Column = 1;
            obj.StepPanel4Layout = uigridlayout(obj.StepPanel4);
            obj.StepPanel4Layout.ColumnWidth = {'1x'};
            obj.StepPanel4Layout.RowHeight = {58, '1x'};
            obj.StepPanel4Layout.Padding = [0 0 0 0];
            obj.StepPanel4Layout.RowSpacing = 4;
            obj.StepHeader4 = uibutton(obj.StepPanel4Layout, 'push');
            obj.StepHeader4.ButtonPushedFcn = @(src, ev) reconstruction_on_step_header_toggled(obj, src, ev);
            obj.StepHeader4.Text = '4. Run and inspect';
            obj.StepHeader4.WordWrap = 'on';
            obj.StepHeader4.Layout.Row = 1;
            obj.StepHeader4.Layout.Column = 1;
            obj.GridLayoutS4 = uigridlayout(obj.StepPanel4Layout);
            obj.GridLayoutS4.ColumnWidth = {'fit', '1x'};
            % Mesh options; Run, Resume and Cancel; the runs; what to do
            % with the selected run (in one place only); the viewer's
            % messages. The output paths are in the tooltip of Open run folder.
            % Rows 1-4 hold the sub-panel of the settings for the next run.
            % Row 1 is 70 px for the sub-panel's own row of Cloud used to
            % build the mesh
            obj.GridLayoutS4.RowHeight = [70 26 26 30 100 22 26 26 44];   % row 5: Runs over its list
            obj.GridLayoutS4.Layout.Row = 2;
            obj.GridLayoutS4.Layout.Column = 1;

            % The settings and Run, Resume and Cancel in a sub-panel of
            % their own: they are for the next run, not the selected one
            next_panel = uipanel(obj.GridLayoutS4, 'Title', 'Settings for the next Run, Resume or Redo projection', ...
                'Tag', 'ReconstructionNextRunPanel');
            next_panel.Layout.Row = [1 4];
            next_panel.Layout.Column = [1 2];
            next_grid = uigridlayout(next_panel, [5 2]);
            next_grid.ColumnWidth = {'fit', '1x'};
            next_grid.RowHeight = {22, 22, 22, 22, 26};
            next_grid.Padding = [6 4 6 4];
            next_grid.RowSpacing = 4;

            % Mesh options, read by Run and Resume and passed to the
            % mesh step (mesh_method and cloud_source). Row 1: the mesh
            % method; row 2: the dense clouds of a new run ("Clouds to
            % compute"); row 3: the cloud the mesh is made from ("Cloud used
            % to build the mesh", a choice only when both clouds are made).
            % The labels say what they choose, so the two are not read as
            % the same choice. The mesh cloud has its own row: next to Mesh
            % method its label would leave the drop-down no width.
            obj.ReconstructionMeshMethodLabel = uilabel(next_grid);
            obj.ReconstructionMeshMethodLabel.Text = 'Mesh method';
            obj.ReconstructionMeshMethodLabel.Layout.Row = 1;
            obj.ReconstructionMeshMethodLabel.Layout.Column = 1;

            obj.ReconstructionMeshMethodDropDown = uidropdown(next_grid);
            obj.ReconstructionMeshMethodDropDown.Items = {'Membrane fit', 'Alpha shape'};
            obj.ReconstructionMeshMethodDropDown.ItemsData = {'membrane', 'alpha'};
            obj.ReconstructionMeshMethodDropDown.Value = 'membrane';
            obj.ReconstructionMeshMethodDropDown.Tooltip = {'Membrane fit: smooth surface fitted to the dense cloud (default)'; 'Alpha shape: the earlier mesh, kept for comparison'};
            obj.ReconstructionMeshMethodDropDown.Layout.Row = 1;
            obj.ReconstructionMeshMethodDropDown.Layout.Column = 2;

            obj.ReconstructionCloudSourceLabel = uilabel(next_grid);
            obj.ReconstructionCloudSourceLabel.Text = 'Cloud used to build the mesh';
            obj.ReconstructionCloudSourceLabel.Layout.Row = 3;
            obj.ReconstructionCloudSourceLabel.Layout.Column = 1;

            obj.ReconstructionCloudSourceDropDown = uidropdown(next_grid);
            obj.ReconstructionCloudSourceDropDown.Items = {'COLMAP', 'APDe-MVS'};
            obj.ReconstructionCloudSourceDropDown.ItemsData = {'fused', 'apd'};
            obj.ReconstructionCloudSourceDropDown.Value = 'fused';
            obj.ReconstructionCloudSourceDropDown.Layout.Row = 3;
            obj.ReconstructionCloudSourceDropDown.Layout.Column = 2;

            obj.ReconstructionDenseLabel = uilabel(next_grid);
            obj.ReconstructionDenseLabel.Text = 'Clouds to compute';
            obj.ReconstructionDenseLabel.Layout.Row = 2;
            obj.ReconstructionDenseLabel.Layout.Column = 1;

            obj.ReconstructionDenseDropDown = uidropdown(next_grid);
            obj.ReconstructionDenseDropDown.Items = {'COLMAP', 'APDe-MVS + COLMAP'};
            obj.ReconstructionDenseDropDown.ItemsData = {'colmap', 'both'};
            obj.ReconstructionDenseDropDown.Value = obj.reconstruction_dense_by_source.built;
            % The tooltip says why COLMAP is in both choices, and names the
            % mesh-cloud control by its label
            obj.ReconstructionDenseDropDown.Tooltip = {['COLMAP is always needed, for the visibility checks: ' ...
                'the mesh check uses its dense cloud to know which cameras see each point.']; ...
                ['APDe-MVS + COLMAP also computes the APDe-MVS cloud (needs APD.exe, run.py and Python); ' ...
                '"Cloud used to build the mesh" then chooses which of the two the mesh is built from.']};
            obj.ReconstructionDenseDropDown.Layout.Row = 2;
            obj.ReconstructionDenseDropDown.Layout.Column = 2;
            obj.ReconstructionDenseDropDown.ValueChangedFcn = @(src, ev) reconstruction_dense_changed(obj);
            obj.reconstruction_dense_sync();

            % RHYTHM's EDGE rule (dataProjection02 minedgeEDGE): a face no
            % camera sees directly takes the views whose edge weight is at
            % least this. 0.55 is RHYTHM's; a lower value fills more of the
            % rim (e.g. the apex) and is recorded as a deviation. A changed
            % value is marked next to the field.
            obj.ReconstructionEdgeWeightLabel = uilabel(next_grid);
            obj.ReconstructionEdgeWeightLabel.Layout.Row = 4;
            obj.ReconstructionEdgeWeightLabel.Layout.Column = 1;
            obj.ReconstructionEdgeWeightField = uieditfield(next_grid, 'numeric');
            obj.ReconstructionEdgeWeightField.Limits = [0.1 0.9];
            obj.ReconstructionEdgeWeightField.ValueDisplayFormat = '%.2f';
            obj.ReconstructionEdgeWeightField.Value = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            obj.ReconstructionEdgeWeightField.ValueChangedFcn = @(src, ev) reconstruction_edge_weight_changed(obj);
            obj.ReconstructionEdgeWeightField.Layout.Row = 4;
            obj.ReconstructionEdgeWeightField.Layout.Column = 2;
            obj.reconstruction_edge_weight_changed();
            % The mesh's cloud ("Cloud used to build the mesh"): the step list and the gates follow
            % it (the steps themselves follow the dense cloud)
            obj.ReconstructionCloudSourceDropDown.ValueChangedFcn = @(src, ev) reconstruction_cloud_source_changed(obj);

            % Run (the main action), then Resume and Cancel, on one row
            run_row = uigridlayout(next_grid, [1 3]);
            run_row.Padding = [0 0 0 0];
            run_row.ColumnSpacing = 6;
            run_row.Layout.Row = 5;
            run_row.Layout.Column = [1 2];
            obj.ReconstructionRunButton = uibutton(run_row, 'push');
            obj.ReconstructionRunButton.Text = 'Run';
            obj.ReconstructionRunButton.FontWeight = 'bold';
            obj.ReconstructionRunButton.BackgroundColor = obj.primary_colour();
            obj.ReconstructionRunButton.FontColor = [1 1 1];
            obj.ReconstructionRunButton.Tooltip = {obj.reconstruction_static_tip('ReconstructionRunButton')};
            obj.ReconstructionRunButton.ButtonPushedFcn = @(src, event) obj.ReconstructionRunButtonPushed(event);
            obj.ReconstructionRunButton.Layout.Column = 1;

            obj.ReconstructionResumeButton = uibutton(run_row, 'push');
            obj.ReconstructionResumeButton.Text = 'Resume';
            obj.ReconstructionResumeButton.Tooltip = {obj.reconstruction_static_tip('ReconstructionResumeButton')};
            obj.ReconstructionResumeButton.ButtonPushedFcn = @(src, event) obj.ReconstructionResumeButtonPushed(event);
            obj.ReconstructionResumeButton.Layout.Column = 2;

            obj.ReconstructionCancelButton = uibutton(run_row, 'push');
            obj.ReconstructionCancelButton.Text = 'Cancel';
            obj.ReconstructionCancelButton.Tooltip = {obj.reconstruction_static_tip('ReconstructionCancelButton')};
            obj.ReconstructionCancelButton.ButtonPushedFcn = @(src, event) obj.ReconstructionCancelButtonPushed(event);
            obj.ReconstructionCancelButton.Layout.Column = 3;

            % "Runs" with a small Refresh button next to it, and the list
            % under them across the row's whole width, so a line "<run id>
            % [COMPLETED · NOT FOR ANALYSIS]" fits without a horizontal
            % scroll bar, and the list is high enough for three runs
            runs_row = uigridlayout(obj.GridLayoutS4, [2 1]);
            runs_row.Padding = [0 0 0 0];
            runs_row.RowSpacing = 2;
            runs_row.ColumnWidth = {'1x'};
            runs_row.RowHeight = {24, '1x'};
            runs_row.Layout.Row = 5;
            runs_row.Layout.Column = [1 2];
            runs_head = uigridlayout(runs_row, [1 3]);
            runs_head.Padding = [0 0 0 0];
            runs_head.ColumnWidth = {'fit', 28, '1x'};
            runs_head.RowHeight = {24};
            runs_head.Layout.Row = 1;
            runs_head.Layout.Column = 1;
            obj.ReconstructionRunListLabel = uilabel(runs_head);
            obj.ReconstructionRunListLabel.Text = 'Runs';
            obj.ReconstructionRunListLabel.Layout.Row = 1;
            obj.ReconstructionRunListLabel.Layout.Column = 1;
            obj.ReconstructionRefreshButton = uibutton(runs_head, 'push');
            obj.ReconstructionRefreshButton.Text = char(8635);
            obj.ReconstructionRefreshButton.Tooltip = {'Refresh: read the runs and their status from disk again.'};
            obj.ReconstructionRefreshButton.ButtonPushedFcn = @(src, event) obj.ReconstructionRefreshButtonPushed(event);
            obj.ReconstructionRefreshButton.Layout.Row = 1;
            obj.ReconstructionRefreshButton.Layout.Column = 2;

            obj.ReconstructionRunList = uilistbox(runs_row);
            obj.ReconstructionRunList.ValueChangedFcn = @(src, ev) ReconstructionRunListValueChanged(obj, src, ev);
            obj.ReconstructionRunList.Items = {};
            obj.ReconstructionRunList.Layout.Row = 2;
            obj.ReconstructionRunList.Layout.Column = 1;

            % What to do with the selected run: Visualise (the main
            % action), Redo projection..., Reproject from files... (any
            % model and mesh, outside a run) and Open run folder
            act = uigridlayout(obj.GridLayoutS4, [2 2]);
            act.Padding = [0 0 0 0];
            act.RowSpacing = 4;
            act.ColumnSpacing = 6;
            act.RowHeight = {26, 26};
            act.Layout.Row = [7 8];
            act.Layout.Column = [1 2];
            obj.ReconstructionVisualiseButton = uibutton(act, 'push');
            obj.ReconstructionVisualiseButton.Text = 'Visualise';
            obj.ReconstructionVisualiseButton.FontWeight = 'bold';
            obj.ReconstructionVisualiseButton.BackgroundColor = obj.primary_colour();
            obj.ReconstructionVisualiseButton.FontColor = [1 1 1];
            obj.ReconstructionVisualiseButton.Tooltip = {obj.reconstruction_static_tip('ReconstructionVisualiseButton')};
            obj.ReconstructionVisualiseButton.ButtonPushedFcn = @(src, event) obj.ReconstructionVisualiseButtonPushed(event);
            obj.ReconstructionVisualiseButton.Layout.Row = 1;
            obj.ReconstructionVisualiseButton.Layout.Column = 1;

            % Redo projection: the selected run's projection step, pending
            % or done again (rabbit_reconstruction_tab.can_redo_reprojection)
            obj.ReconstructionReprojectButton = uibutton(act, 'push');
            obj.ReconstructionReprojectButton.Text = 'Redo projection...';
            obj.ReconstructionReprojectButton.Tooltip = {obj.reconstruction_static_tip('ReconstructionReprojectButton')};
            obj.ReconstructionReprojectButton.ButtonPushedFcn = @(src, event) obj.ReconstructionReprojectButtonPushed(event);
            obj.ReconstructionReprojectButton.Layout.Row = 1;
            obj.ReconstructionReprojectButton.Layout.Column = 2;

            obj.ReconstructionReprojectFilesButton = uibutton(act, 'push');
            obj.ReconstructionReprojectFilesButton.Text = 'Reproject from files...';
            obj.ReconstructionReprojectFilesButton.Tooltip = {['Project the activation map, and the OM video if wanted, onto ' ...
                'a COLMAP model and mesh that you choose, outside a run (RHYTHM, Gloschat et al. 2018).']};
            obj.ReconstructionReprojectFilesButton.ButtonPushedFcn = @(src, event) obj.ReconstructionReprojectFilesButtonPushed(event);
            obj.ReconstructionReprojectFilesButton.Layout.Row = 2;
            obj.ReconstructionReprojectFilesButton.Layout.Column = 1;

            obj.ReconstructionOpenRunFolderButton = uibutton(act, 'push');
            obj.ReconstructionOpenRunFolderButton.Text = 'Open run folder';
            obj.ReconstructionOpenRunFolderButton.Tooltip = {'Select a run first.'};
            obj.ReconstructionOpenRunFolderButton.ButtonPushedFcn = @(src, event) reconstruction_open_run_folder(obj);
            obj.ReconstructionOpenRunFolderButton.Layout.Row = 2;
            obj.ReconstructionOpenRunFolderButton.Layout.Column = 2;

            % The output paths, filled from the run manifest by Visualise.
            % Not shown: Open run folder names them in its tooltip.
            obj.VisualiseFusedLabel = uilabel(obj.GridLayoutS4, 'Text', 'Fused point cloud path', 'Visible', 'off');
            obj.VisualiseFusedField = uieditfield(obj.GridLayoutS4, 'text', 'Editable', 'off', 'Value', '-', 'Visible', 'off');
            obj.VisualiseRebuiltLabel = uilabel(obj.GridLayoutS4, 'Text', 'Mesh path', 'Visible', 'off');
            obj.VisualiseRebuiltField = uieditfield(obj.GridLayoutS4, 'text', 'Editable', 'off', 'Value', '-', 'Visible', 'off');
            obj.VisualiseProjectedLabel = uilabel(obj.GridLayoutS4, 'Text', 'Projected activation path', 'Visible', 'off');
            obj.VisualiseProjectedField = uieditfield(obj.GridLayoutS4, 'text', 'Editable', 'off', 'Value', '-', 'Visible', 'off');
            for h = {obj.VisualiseFusedLabel, obj.VisualiseFusedField, obj.VisualiseRebuiltLabel, ...
                    obj.VisualiseRebuiltField, obj.VisualiseProjectedLabel, obj.VisualiseProjectedField}
                h{1}.Layout.Row = 9;
                h{1}.Layout.Column = 1;
            end

            obj.VisualiseStatusText = uitextarea(obj.GridLayoutS4);
            obj.VisualiseStatusText.Editable = 'off';
            obj.VisualiseStatusText.Value = {'Select a run, then Visualise.'};
            obj.VisualiseStatusText.Tooltip = {'Messages from the viewer.'};
            obj.VisualiseStatusText.Layout.Row = 9;
            obj.VisualiseStatusText.Layout.Column = [1 2];

            obj.ReconstructionRunListEmptyLabel = uilabel(obj.GridLayoutS4);
            obj.ReconstructionRunListEmptyLabel.Text = 'No runs yet: press Run to make the first one.';
            obj.ReconstructionRunListEmptyLabel.Layout.Row = 6;
            obj.ReconstructionRunListEmptyLabel.Layout.Column = [1 2];

            % ---- ToolsPanel (copy-on-write tools) ----
            obj.ToolsPanel = uipanel(obj.GridLayoutR1);
            obj.ToolsPanel.BorderType = 'none';
            obj.ToolsPanel.Layout.Row = 5;
            obj.ToolsPanel.Layout.Column = 1;
            obj.ToolsPanelLayout = uigridlayout(obj.ToolsPanel);
            obj.ToolsPanelLayout.ColumnWidth = {'1x'};
            obj.ToolsPanelLayout.RowHeight = {58, '1x'};
            obj.ToolsPanelLayout.Padding = [0 0 0 0];
            obj.ToolsPanelLayout.RowSpacing = 4;
            obj.ToolsHeader = uibutton(obj.ToolsPanelLayout, 'push');
            obj.ToolsHeader.ButtonPushedFcn = @(src, ev) reconstruction_on_tools_header_toggled(obj, src, ev);
            obj.ToolsHeader.Text = 'Edit tools';
            obj.ToolsHeader.Tooltip = {'Show or hide the mesh and point-cloud edit tools. Edits are saved as new files; the run''s own files are never changed.'};
            obj.ToolsHeader.WordWrap = 'on';
            obj.ToolsHeader.Layout.Row = 1;
            obj.ToolsHeader.Layout.Column = 1;

            % ---- CopyOnWritePanel ----
            % This is the single visible child of ToolsPanelLayout. A
            % scrollable inner grid keeps the four subsections reachable in
            % small windows while preserving one shared source/status
            % contract and unambiguous ownership at runtime.
            obj.CopyOnWritePanel = uigridlayout(obj.ToolsPanelLayout);
            obj.CopyOnWritePanel.ColumnWidth = {'1x'};
            obj.CopyOnWritePanel.RowHeight = [128 24 156 60 264 242 242 286];
            obj.CopyOnWritePanel.Scrollable = 'on';
            obj.CopyOnWritePanel.Layout.Row = 2;
            obj.CopyOnWritePanel.Layout.Column = 1;
            obj.ToolsPanelLayout.Visible = 'on';

            obj.CopyOnWriteContractLabel = uilabel(obj.CopyOnWritePanel);
            obj.CopyOnWriteContractLabel.Text = ['Your source files are never changed. Preview shows the result on screen only; nothing is saved. ' ...
                'Apply to copy saves the result as a new file and records it with the run. The source, settings and view must still match the preview, so change nothing between Preview and Apply. ' ...
                'Reset clears the preview; it does not delete a copy you already saved. These tools edit geometry for display only; they do not change activation values.'];
            obj.CopyOnWriteContractLabel.WordWrap = 'on';
            obj.CopyOnWriteContractLabel.Layout.Row = 1;
            obj.CopyOnWriteContractLabel.Layout.Column = 1;

            obj.CopyOnWriteSummaryLabel = uilabel(obj.CopyOnWritePanel);
            obj.CopyOnWriteSummaryLabel.Text = ['Selected run: No run selected. The source file for touch-up, intensity, area and smoothing appears here once a run is selected. ' ...
                'Area removal and smoothing also remember the 3-D view in which you made the selection.'];
            obj.CopyOnWriteSummaryLabel.WordWrap = 'on';
            obj.CopyOnWriteSummaryLabel.Layout.Row = 3;
            obj.CopyOnWriteSummaryLabel.Layout.Column = 1;

            obj.CopyOnWriteStatusLabel = uilabel(obj.CopyOnWritePanel);
            obj.CopyOnWriteStatusLabel.Text = 'No run selected. Select a run to use these tools.';
            obj.CopyOnWriteStatusLabel.FontWeight = 'bold';
            obj.CopyOnWriteStatusLabel.WordWrap = 'on';
            obj.CopyOnWriteStatusLabel.Layout.Row = 4;
            obj.CopyOnWriteStatusLabel.Layout.Column = 1;

            obj.TouchupPanel = uipanel(obj.CopyOnWritePanel);
            obj.TouchupPanel.Title = 'Mesh touch-up';
            obj.TouchupPanel.Layout.Row = 5;
            obj.TouchupPanel.Layout.Column = 1;
            obj.GridLayoutT1 = uigridlayout(obj.TouchupPanel);
            obj.GridLayoutT1.ColumnWidth = {'1x', '2x'};
            obj.GridLayoutT1.RowHeight = [22 22 22 22 22 22 22 22 22 22 22];

            obj.TouchupSectionLabel = uilabel(obj.GridLayoutT1);
            obj.TouchupSectionLabel.Text = 'Mesh touch-up';
            obj.TouchupSectionLabel.FontWeight = 'bold';
            obj.TouchupSectionLabel.Layout.Row = 1;
            obj.TouchupSectionLabel.Layout.Column = [1 2];

            obj.TouchupSourceField = uieditfield(obj.GridLayoutT1, 'text');
            obj.TouchupSourceField.Editable = 'off';
            obj.TouchupSourceField.Value = 'Source: -';
            obj.TouchupSourceField.Layout.Row = 2;
            obj.TouchupSourceField.Layout.Column = [1 2];

            obj.TouchupOpDropDown = uidropdown(obj.GridLayoutT1);
            obj.TouchupOpDropDown.Items = {'Remove box', 'Remove small components'};
            obj.TouchupOpDropDown.Value = 'Remove box';
            obj.TouchupOpDropDown.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.TouchupOpDropDown.Tooltip = {'Remove box: delete the faces whose centre lies inside a box. Remove small components: delete separate pieces with fewer faces than the threshold.'};
            obj.TouchupOpDropDown.Layout.Row = 3;
            obj.TouchupOpDropDown.Layout.Column = [1 2];

            obj.TouchupBoxField = uieditfield(obj.GridLayoutT1, 'text');
            obj.TouchupBoxField.Value = '';
            obj.TouchupBoxField.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.TouchupBoxField.Tooltip = {'Box as 6 numbers: xlo xhi ylo yhi zlo zhi, in the run''s units: mm when a calibration was applied, otherwise the COLMAP model''s own units.'};
            obj.TouchupBoxField.Layout.Row = 4;
            obj.TouchupBoxField.Layout.Column = [1 2];

            obj.TouchupMinFacesField = uieditfield(obj.GridLayoutT1, 'numeric');
            obj.TouchupMinFacesField.Limits = [1 Inf];
            obj.TouchupMinFacesField.Value = 10;
            obj.TouchupMinFacesField.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.TouchupMinFacesField.Tooltip = {'Remove separate pieces of the mesh with fewer than this many faces.'};
            obj.TouchupMinFacesField.Layout.Row = 5;
            obj.TouchupMinFacesField.Layout.Column = [1 2];

            obj.TouchupPreviewButton = uibutton(obj.GridLayoutT1, 'push');
            obj.TouchupPreviewButton.Text = 'Preview';
            obj.TouchupPreviewButton.ButtonPushedFcn = @(src, event) obj.ReconstructionTouchupPreviewButtonPushed(event);
            obj.TouchupPreviewButton.Layout.Row = 6;
            obj.TouchupPreviewButton.Layout.Column = [1 2];

            obj.TouchupApplyButton = uibutton(obj.GridLayoutT1, 'push');
            obj.TouchupApplyButton.Text = 'Apply to copy';
            obj.TouchupApplyButton.ButtonPushedFcn = @(src, event) obj.ReconstructionTouchupApplyButtonPushed(event);
            obj.TouchupApplyButton.Layout.Row = 7;
            obj.TouchupApplyButton.Layout.Column = [1 2];

            obj.TouchupResetButton = uibutton(obj.GridLayoutT1, 'push');
            obj.TouchupResetButton.Text = 'Cancel / Reset';
            obj.TouchupResetButton.ButtonPushedFcn = @(src, event) obj.ReconstructionTouchupResetButtonPushed(event);
            obj.TouchupResetButton.Tooltip = {'Clear the preview. A copy you already saved is kept.'};
            obj.TouchupResetButton.Layout.Row = 8;
            obj.TouchupResetButton.Layout.Column = [1 2];

            obj.TouchupOutputField = uieditfield(obj.GridLayoutT1, 'text');
            obj.TouchupOutputField.Editable = 'off';
            obj.TouchupOutputField.Value = 'Output: -';
            obj.TouchupOutputField.Layout.Row = 9;
            obj.TouchupOutputField.Layout.Column = [1 2];

            obj.TouchupStatusText = uitextarea(obj.GridLayoutT1);
            obj.TouchupStatusText.Editable = 'off';
            obj.TouchupStatusText.Value = {'Touch-up saves a new copy; the source file is never changed.'};
            obj.TouchupStatusText.Layout.Row = 10;
            obj.TouchupStatusText.Layout.Column = [1 2];
            % Dense-point intensity filtering (copy-on-write). The
            % intensity scalar is the
            % RGB luma/display proxy (0.299R+0.587G+0.114B), not calibrated light intensity; the threshold
            % is an integer 0..255 with inclusive semantics ('Below'
            % keeps >= threshold, 'Above' keeps <= threshold; equality
            % retained). Apply writes a new versioned PLY under
            % outputs/intensity_filters/ + regenerated .vis + manifest
            % record; the source PLY is never overwritten. Faces are
            % not remapped: the output is
            % point-cloud-only.)

            obj.TouchupComposeLabel = uilabel(obj.GridLayoutT1);
            obj.TouchupComposeLabel.Text = 'Always starts from the mesh the run made; earlier saved edits are not included.';
            obj.TouchupComposeLabel.Layout.Row = 11;
            obj.TouchupComposeLabel.Layout.Column = [1 2];

            obj.IntensityPanel = uipanel(obj.CopyOnWritePanel);
            obj.IntensityPanel.Title = 'Dense-point intensity filter';
            obj.IntensityPanel.Layout.Row = 6;
            obj.IntensityPanel.Layout.Column = 1;
            obj.GridLayoutT2 = uigridlayout(obj.IntensityPanel);
            obj.GridLayoutT2.ColumnWidth = {'1x', '2x'};
            obj.GridLayoutT2.RowHeight = [22 22 22 22 22 22 22 22 22 22];

            obj.IntensitySectionLabel = uilabel(obj.GridLayoutT2);
            obj.IntensitySectionLabel.Text = 'Dense-point intensity filter';
            obj.IntensitySectionLabel.FontWeight = 'bold';
            obj.IntensitySectionLabel.Layout.Row = 1;
            obj.IntensitySectionLabel.Layout.Column = [1 2];

            obj.IntensitySourceField = uieditfield(obj.GridLayoutT2, 'text');
            obj.IntensitySourceField.Editable = 'off';
            obj.IntensitySourceField.Value = 'Source: -';
            obj.IntensitySourceField.Layout.Row = 2;
            obj.IntensitySourceField.Layout.Column = [1 2];

            obj.IntensityModeDropDown = uidropdown(obj.GridLayoutT2);
            obj.IntensityModeDropDown.Items = {'Below threshold (keep >=)', 'Above threshold (keep <=)'};
            obj.IntensityModeDropDown.Value = 'Below threshold (keep >=)';
            obj.IntensityModeDropDown.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.IntensityModeDropDown.Tooltip = {'Below threshold: keep points at least as bright as the threshold. Above threshold: keep points no brighter than it. Brightness is the point colour, not an optical mapping signal.'};
            obj.IntensityModeDropDown.Layout.Row = 3;
            obj.IntensityModeDropDown.Layout.Column = [1 2];

            obj.IntensityThresholdField = uieditfield(obj.GridLayoutT2, 'numeric');
            obj.IntensityThresholdField.Limits = [0 255];
            obj.IntensityThresholdField.Value = 128;
            obj.IntensityThresholdField.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.IntensityThresholdField.Tooltip = {'Brightness threshold, a whole number from 0 to 255 (0.299 R + 0.587 G + 0.114 B of the point colour).'};
            obj.IntensityThresholdField.Layout.Row = 4;
            obj.IntensityThresholdField.Layout.Column = [1 2];

            obj.IntensityPreviewButton = uibutton(obj.GridLayoutT2, 'push');
            obj.IntensityPreviewButton.Text = 'Preview';
            obj.IntensityPreviewButton.ButtonPushedFcn = @(src, event) obj.ReconstructionIntensityPreviewButtonPushed(event);
            obj.IntensityPreviewButton.Layout.Row = 5;
            obj.IntensityPreviewButton.Layout.Column = [1 2];

            obj.IntensityApplyButton = uibutton(obj.GridLayoutT2, 'push');
            obj.IntensityApplyButton.Text = 'Apply to copy';
            obj.IntensityApplyButton.ButtonPushedFcn = @(src, event) obj.ReconstructionIntensityApplyButtonPushed(event);
            obj.IntensityApplyButton.Layout.Row = 6;
            obj.IntensityApplyButton.Layout.Column = [1 2];

            obj.IntensityResetButton = uibutton(obj.GridLayoutT2, 'push');
            obj.IntensityResetButton.Text = 'Cancel / Reset';
            obj.IntensityResetButton.ButtonPushedFcn = @(src, event) obj.ReconstructionIntensityResetButtonPushed(event);
            obj.IntensityResetButton.Tooltip = {'Clear the preview. A copy you already saved is kept.'};
            obj.IntensityResetButton.Layout.Row = 7;
            obj.IntensityResetButton.Layout.Column = [1 2];

            obj.IntensityOutputField = uieditfield(obj.GridLayoutT2, 'text');
            obj.IntensityOutputField.Editable = 'off';
            obj.IntensityOutputField.Value = 'Output: -';
            obj.IntensityOutputField.Layout.Row = 8;
            obj.IntensityOutputField.Layout.Column = [1 2];

            obj.IntensityStatusText = uitextarea(obj.GridLayoutT2);
            obj.IntensityStatusText.Editable = 'off';
            obj.IntensityStatusText.Value = {'Intensity filtering saves a new copy; the source file is never changed.'};
            obj.IntensityStatusText.Layout.Row = 9;
            obj.IntensityStatusText.Layout.Column = [1 2];
            % 2D screen-area point removal (copy-on-write,
            % independent of intensity filtering). Select a 2D area in
            % the 3D dense-reconstruction view (rectangle or lasso,
            % drawn in the z=0 data plane) and remove all points in that
            % area. The selection is tied to the camera at draw time:
            % points whose projection through that camera falls inside
            % the projected polygon are removed. Apply writes a new
            % versioned PLY under outputs/area_removals/ + regenerated
            % .vis + manifest record; the source PLY is never
            % overwritten. Faces with any vertex inside the selection
            % are removed and the remaining faces are remapped.

            obj.IntensityComposeLabel = uilabel(obj.GridLayoutT2);
            obj.IntensityComposeLabel.Text = 'Filters the fused cloud.';
            obj.IntensityComposeLabel.Layout.Row = 10;
            obj.IntensityComposeLabel.Layout.Column = [1 2];

            obj.AreaPanel = uipanel(obj.CopyOnWritePanel);
            obj.AreaPanel.Title = '2D area removal (screen-space selection)';
            obj.AreaPanel.Layout.Row = 7;
            obj.AreaPanel.Layout.Column = 1;
            obj.GridLayoutT3 = uigridlayout(obj.AreaPanel);
            obj.GridLayoutT3.ColumnWidth = {'1x', '2x'};
            obj.GridLayoutT3.RowHeight = [22 22 22 22 22 22 22 22 22 22];

            obj.AreaSectionLabel = uilabel(obj.GridLayoutT3);
            obj.AreaSectionLabel.Text = '2D area removal (screen-space selection)';
            obj.AreaSectionLabel.FontWeight = 'bold';
            obj.AreaSectionLabel.Layout.Row = 1;
            obj.AreaSectionLabel.Layout.Column = [1 2];

            obj.AreaSourceField = uieditfield(obj.GridLayoutT3, 'text');
            obj.AreaSourceField.Editable = 'off';
            obj.AreaSourceField.Value = 'Source: -';
            obj.AreaSourceField.Layout.Row = 2;
            obj.AreaSourceField.Layout.Column = [1 2];

            obj.AreaShapeDropDown = uidropdown(obj.GridLayoutT3);
            obj.AreaShapeDropDown.Items = {'Rectangle (drag)', 'Lasso (click vertices)'};
            obj.AreaShapeDropDown.Value = 'Rectangle (drag)';
            obj.AreaShapeDropDown.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.AreaShapeDropDown.Tooltip = {'Rectangle: drag a box in the 3D view. Lasso: click vertices to trace a polygon, then double-click to finish.'};
            obj.AreaShapeDropDown.Layout.Row = 3;
            obj.AreaShapeDropDown.Layout.Column = [1 2];

            obj.AreaSelectButton = uibutton(obj.GridLayoutT3, 'push');
            obj.AreaSelectButton.Text = 'Select area in 3D view';
            obj.AreaSelectButton.ButtonPushedFcn = @(src, event) obj.ReconstructionAreaSelectButtonPushed(event);
            obj.AreaSelectButton.Layout.Row = 4;
            obj.AreaSelectButton.Layout.Column = [1 2];

            obj.AreaPreviewButton = uibutton(obj.GridLayoutT3, 'push');
            obj.AreaPreviewButton.Text = 'Preview';
            obj.AreaPreviewButton.ButtonPushedFcn = @(src, event) obj.ReconstructionAreaPreviewButtonPushed(event);
            obj.AreaPreviewButton.Layout.Row = 5;
            obj.AreaPreviewButton.Layout.Column = [1 2];

            obj.AreaApplyButton = uibutton(obj.GridLayoutT3, 'push');
            obj.AreaApplyButton.Text = 'Apply to copy';
            obj.AreaApplyButton.ButtonPushedFcn = @(src, event) obj.ReconstructionAreaApplyButtonPushed(event);
            obj.AreaApplyButton.Layout.Row = 6;
            obj.AreaApplyButton.Layout.Column = [1 2];

            obj.AreaResetButton = uibutton(obj.GridLayoutT3, 'push');
            obj.AreaResetButton.Text = 'Cancel / Reset';
            obj.AreaResetButton.ButtonPushedFcn = @(src, event) obj.ReconstructionAreaResetButtonPushed(event);
            obj.AreaResetButton.Tooltip = {'Clear the selection and preview. A copy you already saved is kept.'};
            obj.AreaResetButton.Layout.Row = 7;
            obj.AreaResetButton.Layout.Column = [1 2];

            obj.AreaOutputField = uieditfield(obj.GridLayoutT3, 'text');
            obj.AreaOutputField.Editable = 'off';
            obj.AreaOutputField.Value = 'Output: -';
            obj.AreaOutputField.Layout.Row = 8;
            obj.AreaOutputField.Layout.Column = [1 2];

            obj.AreaStatusText = uitextarea(obj.GridLayoutT3);
            obj.AreaStatusText.Editable = 'off';
            obj.AreaStatusText.Value = {'Area removal saves a new copy; the source file is never changed.'};
            obj.AreaStatusText.Layout.Row = 9;
            obj.AreaStatusText.Layout.Column = [1 2];
            % Bounded circular mesh smoothing (copy-on-write,
            % topology-safe). Click a brush center in the 3D view; the
            % vertices within the screen-space radius are smoothed with
            % a damped Laplacian for the given number of iterations.
            % The brush boundary ring is pinned (never moves), so the
            % smoothed patch stays anchored to the surrounding mesh.
            % Connectivity and all vertex attributes are preserved.
            % Apply writes a new versioned PLY under
            % outputs/smoothings/ + regenerated .vis + manifest record;
            % the source PLY is never overwritten.

            obj.AreaComposeLabel = uilabel(obj.GridLayoutT3);
            obj.AreaComposeLabel.Text = 'Removes from the current source (latest derived output, else fused).';
            obj.AreaComposeLabel.Layout.Row = 10;
            obj.AreaComposeLabel.Layout.Column = [1 2];

            obj.SmoothPanel = uipanel(obj.CopyOnWritePanel);
            obj.SmoothPanel.Title = 'Bounded circular smoothing (screen-space brush)';
            obj.SmoothPanel.Layout.Row = 8;
            obj.SmoothPanel.Layout.Column = 1;
            obj.GridLayoutT4 = uigridlayout(obj.SmoothPanel);
            obj.GridLayoutT4.ColumnWidth = {'1x', '2x'};
            obj.GridLayoutT4.RowHeight = [22 22 22 22 22 22 22 22 22 22 22 22];

            obj.SmoothSectionLabel = uilabel(obj.GridLayoutT4);
            obj.SmoothSectionLabel.Text = 'Bounded circular smoothing (screen-space brush)';
            obj.SmoothSectionLabel.FontWeight = 'bold';
            obj.SmoothSectionLabel.Layout.Row = 1;
            obj.SmoothSectionLabel.Layout.Column = [1 2];

            obj.SmoothSourceField = uieditfield(obj.GridLayoutT4, 'text');
            obj.SmoothSourceField.Editable = 'off';
            obj.SmoothSourceField.Value = 'Source: -';
            obj.SmoothSourceField.Layout.Row = 2;
            obj.SmoothSourceField.Layout.Column = [1 2];

            obj.SmoothRadiusField = uieditfield(obj.GridLayoutT4, 'numeric');
            obj.SmoothRadiusField.Limits = [1 Inf];
            obj.SmoothRadiusField.Value = 40;
            obj.SmoothRadiusField.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.SmoothRadiusField.Tooltip = {'Brush radius in screen pixels.'};
            obj.SmoothRadiusField.Layout.Row = 3;
            obj.SmoothRadiusField.Layout.Column = [1 2];

            obj.SmoothIterationsField = uieditfield(obj.GridLayoutT4, 'numeric');
            obj.SmoothIterationsField.Limits = [1 50];
            obj.SmoothIterationsField.Value = 5;
            obj.SmoothIterationsField.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.SmoothIterationsField.Tooltip = {'Smoothing iterations (1..50).'};
            obj.SmoothIterationsField.Layout.Row = 4;
            obj.SmoothIterationsField.Layout.Column = [1 2];

            obj.SmoothStrengthField = uieditfield(obj.GridLayoutT4, 'numeric');
            obj.SmoothStrengthField.Limits = [0 1];
            obj.SmoothStrengthField.Value = 0.5;
            obj.SmoothStrengthField.ValueChangedFcn = @(src, ev) ReconstructionEditControlChanged(obj, src, ev);
            obj.SmoothStrengthField.Tooltip = {'Smoothing strength from 0 to 1 (1 moves each point fully to the average of its neighbours).'};
            obj.SmoothStrengthField.Layout.Row = 5;
            obj.SmoothStrengthField.Layout.Column = [1 2];

            obj.SmoothSelectButton = uibutton(obj.GridLayoutT4, 'push');
            obj.SmoothSelectButton.Text = 'Select brush centre in 3D view';
            obj.SmoothSelectButton.ButtonPushedFcn = @(src, event) obj.ReconstructionSmoothSelectButtonPushed(event);
            obj.SmoothSelectButton.Layout.Row = 6;
            obj.SmoothSelectButton.Layout.Column = [1 2];

            obj.SmoothPreviewButton = uibutton(obj.GridLayoutT4, 'push');
            obj.SmoothPreviewButton.Text = 'Preview';
            obj.SmoothPreviewButton.ButtonPushedFcn = @(src, event) obj.ReconstructionSmoothPreviewButtonPushed(event);
            obj.SmoothPreviewButton.Layout.Row = 7;
            obj.SmoothPreviewButton.Layout.Column = [1 2];

            obj.SmoothApplyButton = uibutton(obj.GridLayoutT4, 'push');
            obj.SmoothApplyButton.Text = 'Apply to copy';
            obj.SmoothApplyButton.ButtonPushedFcn = @(src, event) obj.ReconstructionSmoothApplyButtonPushed(event);
            obj.SmoothApplyButton.Layout.Row = 8;
            obj.SmoothApplyButton.Layout.Column = [1 2];

            obj.SmoothResetButton = uibutton(obj.GridLayoutT4, 'push');
            obj.SmoothResetButton.Text = 'Cancel / Reset';
            obj.SmoothResetButton.ButtonPushedFcn = @(src, event) obj.ReconstructionSmoothResetButtonPushed(event);
            obj.SmoothResetButton.Tooltip = {'Clear the brush and preview. A copy you already saved is kept.'};
            obj.SmoothResetButton.Layout.Row = 9;
            obj.SmoothResetButton.Layout.Column = [1 2];

            obj.SmoothOutputField = uieditfield(obj.GridLayoutT4, 'text');
            obj.SmoothOutputField.Editable = 'off';
            obj.SmoothOutputField.Value = 'Output: -';
            obj.SmoothOutputField.Layout.Row = 10;
            obj.SmoothOutputField.Layout.Column = [1 2];

            obj.SmoothStatusText = uitextarea(obj.GridLayoutT4);
            obj.SmoothStatusText.Editable = 'off';
            obj.SmoothStatusText.Value = {'Smoothing saves a new copy; the source file is never changed.'};
            obj.SmoothStatusText.Layout.Row = 11;
            obj.SmoothStatusText.Layout.Column = [1 2];
            obj.SmoothComposeLabel = uilabel(obj.GridLayoutT4);
            obj.SmoothComposeLabel.Text = 'Continues from the latest saved edit when it is a mesh, else from the mesh the run made.';
            obj.SmoothComposeLabel.Layout.Row = 12;
            obj.SmoothComposeLabel.Layout.Column = [1 2];

            % ---- Steps panel (centre) ----
            obj.StagePipelinePanel = uipanel(obj.GridLayoutR);
            obj.StagePipelinePanel.Title = 'Steps';
            obj.StagePipelinePanel.Layout.Row = 2;
            obj.StagePipelinePanel.Layout.Column = 2;
            obj.StagePipelinePanel.FontWeight = 'bold';

            obj.ResultsPanel = uipanel(obj.GridLayoutR);
            obj.ResultsPanel.Title = 'Results';
            obj.ResultsPanel.Layout.Row = 2;
            obj.ResultsPanel.Layout.Column = 3;
            obj.ResultsPanel.FontWeight = 'bold';

            % Steps box, top to bottom: Show log and Show in a window...;
            % one tile per step; the selected step's warnings (always
            % shown); the log, with its attempt and Open folder, only
            % while Show log is ticked (reconstruction_show_log)
            obj.GridLayoutR2 = uigridlayout(obj.StagePipelinePanel);
            obj.GridLayoutR2.ColumnWidth = {'1x'};
            obj.GridLayoutR2.RowHeight = {24, 304, '1x', 0, 0};
            obj.GridLayoutR2.RowSpacing = 6;

            % Results: the verdict and one row per finding (fixed-width
            % font, rows of at most 78 characters), then Why? (a run the
            % defect rule marks) and Details... (the full text)
            obj.GridLayoutR3 = uigridlayout(obj.ResultsPanel);
            obj.GridLayoutR3.ColumnWidth = {'1x'};
            obj.GridLayoutR3.RowHeight = {'1x', 26};

            steps_top = uigridlayout(obj.GridLayoutR2, [1 3]);
            steps_top.Padding = [0 0 0 0];
            steps_top.ColumnWidth = {'fit', '1x', 'fit'};
            steps_top.Layout.Row = 1;
            steps_top.Layout.Column = 1;
            obj.ReconstructionShowLogCheckBox = uicheckbox(steps_top);
            obj.ReconstructionShowLogCheckBox.Text = 'Show log';
            obj.ReconstructionShowLogCheckBox.Value = false;
            obj.ReconstructionShowLogCheckBox.Tooltip = {'Show the log of the selected step under its warnings.'};
            obj.ReconstructionShowLogCheckBox.ValueChangedFcn = @(src, ev) reconstruction_show_log(obj);
            obj.ReconstructionShowLogCheckBox.Layout.Column = 1;
            log_open = uibutton(steps_top, 'push', 'Text', 'Show in a window...', ...
                'Tooltip', {'The log of the selected step in a large window.'}, ...
                'ButtonPushedFcn', @(~, ~) reconstruction_show_log_window(obj));
            log_open.Layout.Column = 3;

            obj.ReconstructionStageList = uilistbox(obj.GridLayoutR2);
            stage_ids = rabbit_reconstruction_tab.driver_stage_order();
            stage_items = cell(1, numel(stage_ids));
            for k = 1:numel(stage_ids)
                stage_items{k} = sprintf('Step %d of %d: %s', k, numel(stage_ids), obj.reconstruction_stage_label(stage_ids{k}, stage_ids));
            end
            obj.ReconstructionStageList.Items = stage_items;
            obj.ReconstructionStageList.ItemsData = stage_ids;
            obj.ReconstructionStageList.Tooltip = {'Select a step to see its warnings and log.'};
            obj.ReconstructionStageList.ValueChangedFcn = @(src, ev) ReconstructionStageListValueChanged(obj, src, ev);
            obj.ReconstructionStageList.Layout.Row = 2;
            obj.ReconstructionStageList.Layout.Column = 1;
            % The list box keeps the steps and the selection but cannot
            % colour its rows, so the steps are shown as a column of
            % one-line tiles instead
            obj.ReconstructionStageList.Visible = 'off';

            obj.StageRowsGrid = uigridlayout(obj.GridLayoutR2);
            obj.StageRowsGrid.ColumnWidth = {64, '1x'};
            obj.StageRowsGrid.Scrollable = 'on';
            obj.StageRowsGrid.Padding = [2 2 2 2];
            obj.StageRowsGrid.RowSpacing = 4;
            obj.StageRowsGrid.ColumnSpacing = 4;
            obj.StageRowsGrid.Layout.Row = 2;
            obj.StageRowsGrid.Layout.Column = 1;

            % The selected step's warnings: one line each, with the check's
            % plain name, the measured value and its limit
            obj.StepWarningsText = uitextarea(obj.GridLayoutR2);
            obj.StepWarningsText.Editable = 'off';
            obj.StepWarningsText.Value = {'Select a run to see the warnings of its steps.'};
            obj.StepWarningsText.Tooltip = {'The warnings of the selected step, with the measured values and their limits.'};
            obj.StepWarningsText.Layout.Row = 3;
            obj.StepWarningsText.Layout.Column = 1;

            % The log's header: which attempt of the step, and its folder
            log_head = uigridlayout(obj.GridLayoutR2, [1 4]);
            log_head.Padding = [0 0 0 0];
            log_head.ColumnWidth = {'fit', 'fit', '1x', 'fit'};
            log_head.Layout.Row = 4;
            log_head.Layout.Column = 1;
            obj.ReconstructionLogLabel = uilabel(log_head);
            obj.ReconstructionLogLabel.Text = 'Log';
            obj.ReconstructionLogLabel.FontWeight = 'bold';
            obj.ReconstructionLogLabel.Layout.Column = 1;
            obj.ReconstructionAttemptLabel = uilabel(log_head);
            obj.ReconstructionAttemptLabel.Text = 'Attempt';
            obj.ReconstructionAttemptLabel.Layout.Column = 2;
            obj.ReconstructionAttemptDropDown = uidropdown(log_head);
            obj.ReconstructionAttemptDropDown.Items = {'latest'};
            obj.ReconstructionAttemptDropDown.ItemsData = {''};
            obj.ReconstructionAttemptDropDown.Value = '';
            obj.ReconstructionAttemptDropDown.Tooltip = {['The latest attempt of the step, or an earlier one ' ...
                'that a retry kept beside it.']};
            obj.ReconstructionAttemptDropDown.ValueChangedFcn = @(src, ev) reconstruction_show_step_log(obj);
            obj.ReconstructionAttemptDropDown.Layout.Column = 3;
            obj.ReconstructionLogFolderButton = uibutton(log_head, 'push');
            obj.ReconstructionLogFolderButton.Text = 'Open folder';
            obj.ReconstructionLogFolderButton.Tooltip = {'Open the folder of the selected step (or of its attempt).'};
            obj.ReconstructionLogFolderButton.ButtonPushedFcn = @(src, ev) reconstruction_open_step_folder(obj);
            obj.ReconstructionLogFolderButton.Layout.Column = 4;

            obj.ReconstructionLogViewer = uitextarea(obj.GridLayoutR2);
            obj.ReconstructionLogViewer.Editable = 'off';
            obj.ReconstructionLogViewer.Tooltip = {'Log of the selected step.'};
            obj.ReconstructionLogViewer.Layout.Row = 5;
            obj.ReconstructionLogViewer.Layout.Column = 1;
            % Building the sparse model is the default: show its controls
            % and steps from the start, before a dataset is loaded
            obj.reconstruction_show_sparse_source();
            obj.reconstruction_list_new_run_steps();
            obj.reconstruction_show_log();

            % ---- Results panel (right) ----

            obj.ReconstructionResultsText = uitextarea(obj.GridLayoutR3);
            obj.ReconstructionResultsText.Editable = 'off';
            obj.ReconstructionResultsText.Value = {'No run yet. Load a dataset, check the tools, then Run.'};
            obj.ReconstructionResultsText.Tooltip = obj.reconstruction_results_tooltip();
            obj.ReconstructionResultsText.FontName = 'Courier New';
            obj.ReconstructionResultsText.FontSize = 11;   % 78 characters fit at the default window size
            obj.ReconstructionResultsText.Layout.Row = 1;
            obj.ReconstructionResultsText.Layout.Column = 1;
            res_buttons = uigridlayout(obj.GridLayoutR3, [1 3]);
            res_buttons.Padding = [0 0 0 0];
            res_buttons.ColumnWidth = {'1x', 'fit', 'fit'};
            res_buttons.Layout.Row = 2;
            res_buttons.Layout.Column = 1;
            obj.ReconstructionWhyButton = uibutton(res_buttons, 'push');
            obj.ReconstructionWhyButton.Text = 'Why?';
            obj.ReconstructionWhyButton.Tooltip = {'Why this run is not to be used for analysis: the defect rule (Help > Limitations and checks) and this run''s values.'};
            obj.ReconstructionWhyButton.ButtonPushedFcn = @(src, ev) reconstruction_show_why(obj);
            obj.ReconstructionWhyButton.Visible = 'off';
            obj.ReconstructionWhyButton.Layout.Column = 2;
            obj.ReconstructionDetailsButton = uibutton(res_buttons, 'push');
            obj.ReconstructionDetailsButton.Text = 'Details...';
            obj.ReconstructionDetailsButton.Tooltip = {'The selected run''s full text in a window: status, projection check in words, units.'};
            obj.ReconstructionDetailsButton.ButtonPushedFcn = @(src, ev) reconstruction_show_details(obj);
            obj.ReconstructionDetailsButton.Enable = 'off';
            obj.ReconstructionDetailsButton.Layout.Column = 3;

            % createComponents made the tab before History and the menus after
            % Load file partially and Help; put them back in those places
            obj.place_child(obj.OpenReconstructionManifestMenu, host.LoadfilepartiallyMenu, 'after');
            obj.place_child(obj.ReconstructionHelpMenu, host.HelpMenu, 'after');
            obj.place_child(obj.ReconstructionTab, host.HistoryTab, 'before');
            % File > Current app screenshot (app_screenshot), after Workspace
            app_screenshot.attach_menu(host, file_menu);

            % Close the separate modeless Help figure when the app is deleted
            % (the first thing the app's delete did). This does not
            % acknowledge either checklist preference.
            addlistener(host, 'ObjectBeingDestroyed', @(~, ~) obj.reconstruction_close_help());

            % Initial state of the steps
            obj.reconstruction_init_accordion()
        end

        function order = driver_stage_order(~)
            order = rabbit_reconstruction_tab.driver_stage_order();
        end

        function bind_reconstruction_tab_for_test(obj, tab)
            %BIND_RECONSTRUCTION_TAB_FOR_TEST Named headless test hook.
            % Production callbacks never call this method. Test seam for the
            % probes that drive a run (probe_results_box, probe_cv_range and others).
            if ~isa(tab, 'rabbit_reconstruction_tab')
                error('analyse_om:Reconstruction:TestHook', 'Expected a rabbit_reconstruction_tab instance.');
            end
            obj.reconstruction_tab = tab;
        end
    end

    % Reconstruction/Reprojection tab callbacks + helpers
    methods (Access = public)

        % Menu selected function: OpenReconstructionManifestMenu
        function OpenReconstructionManifestMenuSelected(obj, ~)
            % Refuse while a reconstruction run is active.
            if ~obj.reconstruction_assert_no_active_run(), return; end
            % Open a saved run (File > Open Reconstruction Manifest) and go on
            % from it. The manifest and its files are checked before anything
            % in the app changes; nothing on disk is rewritten. Tests set
            % test_manifest_pick instead of the file picker.
            f = 0; p = '';
            % Test seam: test_manifest_pick (probe_restore_gui_safety and the other restore probes)
            if isprop(obj, 'test_manifest_pick') && ~isempty(obj.test_manifest_pick)
                manifest_path = obj.test_manifest_pick;
            else
                % Start where runs are kept: the bound dataset's runs
                % folder, else the loaded recording's folder
                start = '';
                ds = obj.ReconstructionDatasetField.Value;
                if ~isempty(ds) && isfolder(fullfile(ds, 'reconstruction', 'runs'))
                    start = fullfile(ds, 'reconstruction', 'runs');
                elseif isfield(obj.host.file_info, 'path') && ischar(obj.host.file_info.path) && isfolder(obj.host.file_info.path)
                    start = obj.host.file_info.path;
                end
                [f, p] = uigetfile({'*.json', 'Run manifest (manifest.json or manifest.v2.json)'}, ...
                    'Open reconstruction manifest', fullfile(start, 'manifest.json'));
                if isequal(f, 0)
                    return; % cancelled: session unchanged
                end
                manifest_path = fullfile(p, f);
            end
            % A large run takes minutes to check and draw: say so while it
            % does
            [~, run_name] = fileparts(fileparts(manifest_path));
            busy = uiprogressdlg(obj.host.opticalmappingUIFigure, 'Title', 'Open reconstruction manifest', ...
                'Message', sprintf('Checking run %s and drawing its results. A large run can take some minutes.', ...
                run_name), 'Indeterminate', 'on');
            busy_done = onCleanup(@() delete(busy));
            % ---- Step 1: read-only validation (no state mutation). ------
            tab = rabbit_reconstruction_tab();
            [ok, err, info] = tab.open_manifest(manifest_path);
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'Open reconstruction manifest');
                return;
            end
            % ---- Step 2-3: stage the tab-state in memory (no write). ----
            [cand, err2] = tab.load_state_candidate(info.dataset_root, info.dataset_stem);
            if ~isempty(err2) && isempty(fieldnames(cand))
                uialert(obj.host.opticalmappingUIFigure, err2, 'Open reconstruction manifest');
                return;
            end
            [cand2, err3] = tab.record_run_candidate(cand, info.run_id, info.result_status);
            if ~isempty(err3)
                uialert(obj.host.opticalmappingUIFigure, err3, 'Open reconstruction manifest');
                return;
            end
            % ---- Step 4: prepare the view without touching the app. -----
            % (apply_manifest below publishes it; values are computed from
            % `info` only, so no UI mutation can precede the commit.)
            % ---- Step 5: commit the staged state exactly once. ----------
            [ok5, err5] = tab.commit_state_candidate(cand2);
            if ~ok5
                % A pre-commit failure leaves NO sidecar and no other
                % durable restore artefact (the sidecar write happens below,
                % strictly after a successful commit).
                uialert(obj.host.opticalmappingUIFigure, err5, 'Open reconstruction manifest');
                return;
            end
            % ---- Step 5b: sidecar cache after the commit. ----------------
            % Best-effort cache: a failure warns via the summary
            % and the next open retries; it never invalidates the commit.
            if isfield(info, 'sidecar_pending_bytes') && ~isempty(info.sidecar_pending_bytes)
                [sw_ok, sw_err] = tab.write_sidecar_after_commit(info.run_dir, info.sidecar_pending_bytes);
                if ~sw_ok
                    info.sidecar_warning = sprintf(['The run is open, but its updated record (manifest.v2.json) ' ...
                        'could not be saved: %s. It is tried again the next time the run is opened.'], sw_err);
                end
            end
            % ---- Steps 6-7: bind, publish, show the restore summary. ----
            obj.reconstruction_restore_mode = true;
            obj.reconstruction_tab = tab;
            % Test hook: retain the validated open result so a
            % headless test can inspect the restore state without re-deriving
            % it (read-only convenience; never consumed by production paths).
            % Test seam: last_open_info (probe_manifest_moved_run_anomaly)
            obj.last_open_info = info;

            % Bind the validated activation restore state together with the
            % camera restore state; the callback must not pass camera alone.
            if isfield(info, 'activation_map_restore')
                obj.activation_restore_state = info.activation_map_restore;
            else
                obj.activation_restore_state = struct();
            end
            obj.reconstruction_apply_manifest(info);
            obj.activation_restore_run_id = obj.reconstruction_selected_run_id();
            obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Reconstruction manifest opened: run ', obj.activation_restore_run_id, '.'];
            obj.reconstruction_restore_summary(info);
            % Direct manifest loading is valid before an optical stack is
            % loaded.  Startup hides the legacy tab group until a file is
            % loaded, so make the Reconstruction/Reprojection tab visible
            % and select it explicitly for this direct-entry workflow.
            int = get(obj.host.TabGroup, 'Position');
            set(obj.host.TabGroup, 'Position', [int(1), int(2), int(3), floor(obj.host.figure_size(4)./3)]);
            set(obj.host.TabGroup, 'Visible', 'on');
            obj.ReconstructionHelpProgrammaticSelectionDepth = ...
                obj.ReconstructionHelpProgrammaticSelectionDepth + uint32(1);
            help_selection_cleanup = onCleanup( ...
                @() obj.reconstruction_help_end_programmatic_selection());
            obj.host.TabGroup.SelectedTab = obj.ReconstructionTab;
            drawnow;
            clear help_selection_cleanup;
            % ---- Step 8: automatic visualisation (best effort). ---------
            obj.reconstruction_auto_visualise(info);
            % First-run onboarding for restore journey (after commit).
            obj.reconstruction_maybe_show_first_run('restore');
        end

        % Button pushed function: ReconstructionRunButton
        function ReconstructionRunButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('run');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction run');
                return;
            end
            % Push the field tool paths into the backend
            % before any preflight, so the gate and the backend cannot
            % disagree about which executables will run.
            [sync_ok, sync_err] = obj.reconstruction_sync_tool_paths();
            if ~sync_ok
                uialert(obj.host.opticalmappingUIFigure, sync_err, 'Reconstruction state');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('run');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction run');
                return;
            end
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Reconstruction');
                return;
            end
            if ~obj.reconstruction_mesh_choice_ok(obj.ReconstructionMeshMethodDropDown.Value, ...
                    obj.ReconstructionCloudSourceDropDown.Value)
                return;
            end
            source = obj.reconstruction_sparse_source();
            recipe = [];
            if strcmp(source, 'built')
                % Build mode: the recipe must read, and fit the images
                % (cut tile names, four views, tile sizes) before the run
                [recipe, r_err] = obj.reconstruction_sfm_recipe();
                if isempty(recipe)
                    uialert(obj.host.opticalmappingUIFigure, r_err, 'Sparse model recipe');
                    return;
                end
                % Ticked in the segmentation window: the masks come from
                % that segmentation, not the recipe's own (recorded in the
                % run's recipe as masks.source 'folder')
                seg_masks = obj.reconstruction_segmentation_choice();
                if ~isempty(seg_masks)
                    recipe.masks.use = true;
                    recipe.masks.source = 'folder';
                end
                [fit_ok, fit_err] = rabbit_sfm_build.resolve(recipe, struct( ...
                    'images_dir', obj.ReconstructionImagesField.Value, ...
                    'roi_json', obj.ReconstructionRoiField.Value));
                if ~fit_ok
                    uialert(obj.host.opticalmappingUIFigure, fit_err, 'Sparse model recipe');
                    return;
                end
            else
                % Sparse-model validation: reject invalid models before creating run.
                [sm_ok, sm_err] = obj.reconstruction_tab.validate_sparse_model(...
                    obj.ReconstructionSparseField.Value, obj.ReconstructionImagesField.Value);
                if ~sm_ok
                    uialert(obj.host.opticalmappingUIFigure, sm_err, 'Sparse model validation');
                    return;
                end
            end
            % Pre-flight every step of the run (the sparse model steps when
            % it is built; the APDe-MVS steps unless a built run meshes the
            % COLMAP fused cloud).
            stages = rabbit_reconstruction_tab.stage_order_for_source(source, ...
                obj.ReconstructionCloudSourceDropDown.Value, obj.ReconstructionDenseDropDown.Value);
            for k = 1:numel(stages)
                if strcmp(stages{k}, 'sparse_build')
                    [ok, results] = obj.reconstruction_tab.preflight(stages{k}, struct('sfm_recipe', recipe));
                else
                    [ok, results] = obj.reconstruction_tab.preflight(stages{k});
                end
                [stage_ok, stage_message] = obj.reconstruction_preflight_result( ...
                    obj.reconstruction_stage_label(stages{k}, stages), ok, results);
                if ~stage_ok
                    uialert(obj.host.opticalmappingUIFigure, stage_message, 'Reconstruction pre-flight');
                    return;
                end
            end
            % Everything is checked, so the run can start: a recording with
            % runs here can go on in this dataset folder or a new one
            if ~obj.reconstruction_offer_new_dataset_folder()
                return;
            end
            % The reprojection step at the end of the run can project the
            % OM video too: ask once now, as Reproject run does (default
            % Map only), and record the answer
            [frames, fps, video_note, go] = obj.reconstruction_video_choice('Reconstruction run');
            if ~go
                return;
            end
            % The masks from the segmentation, written now (no pickers)
            mask_dir = '';
            if strcmp(source, 'built') && ~isempty(seg_masks)
                [m_ok, mask_dir, m_msg] = rabbit_segmentation_masks.write_for_run(obj.host, ...
                    obj.ReconstructionRoiField.Value, obj.ReconstructionImagesField.Value, seg_masks);
                if ~m_ok
                    uialert(obj.host.opticalmappingUIFigure, sprintf(['The masks from the assisted area segmentation ' ...
                        'could not be made: %s Untick its checkbox to use the run''s own masks.'], m_msg), ...
                        'Reconstruction run');
                    return;
                end
            end
            % Create the run (immutable run ID + input snapshot).
            run_id = obj.reconstruction_tab.new_run_id();
            inputs = struct('sparse_model_dir', obj.ReconstructionSparseField.Value, ...
                'image_list', obj.ReconstructionImagesField.Value, ...
                'roi_json', obj.ReconstructionRoiField.Value, ...
                'dense', obj.ReconstructionDenseDropDown.Value);
            if strcmp(source, 'built')
                inputs.sparse_model_dir = '';
                inputs.sparse_source = 'built';
                inputs.sfm_recipe = recipe;
                inputs.cloud_source = obj.ReconstructionCloudSourceDropDown.Value;
                if ~isempty(mask_dir)
                    inputs.mask_dir = mask_dir;
                    obj.host.history_field.Value{end+1,1} = sprintf(['Run %s: masks from the assisted area ' ...
                        'segmentation (threshold %.2f, smoothen %g), %s'], run_id, seg_masks.threshold, ...
                        seg_masks.sigma_gauss, mask_dir);
                else
                    obj.host.history_field.Value{end+1,1} = sprintf('Run %s: the run''s own masks (recipe: %s)', ...
                        run_id, obj.reconstruction_mask_words(recipe));
                end
                [cal_dir, cal_go, cal_note, cal_differs] = obj.reconstruction_calibration_for_run();
                if ~cal_go, return; end
                if ~isempty(cal_dir)
                    inputs.calibration_dir = cal_dir;
                    inputs.calibration_date_note = cal_note;
                    inputs.calibration_date_differs = cal_differs;
                end
            end
            % start_run creates the run and records it as RUNNING; when the
            % second part fails it removes the new run again (no step has
            % run), so no RUNNING folder is left behind
            [ok, err, run_dir, kept] = obj.reconstruction_tab.start_run(run_id, inputs); %#ok<ASGLU>
            if ~ok && ~kept
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction run');
                return;
            end
            state_ok = ok;
            state_err = err;
            if ~state_ok
                obj.unconfirmed_run_id = run_id;
                obj.ReconstructionResultsText.Value = { ...
                    sprintf('Run %s - STATE NOT CONFIRMED.', run_id), state_err, ...
                    'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                uialert(obj.host.opticalmappingUIFigure, state_err, 'Reconstruction state not confirmed');
                return;
            end
            obj.unconfirmed_run_id = '';
            obj.reconstruction_update_run_list();
            items = obj.ReconstructionRunList.Items;
            for k = 1:numel(items)
                if ~isempty(strfind(items{k}, run_id))
                    obj.ReconstructionRunList.Value = items{k};
                    break;
                end
            end
            obj.reconstruction_render_status(run_id);
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            drawnow;

            % Drive the pipeline with a progress dialog (step k of N).
            % The dialog's Cancel uses the same request as the Cancel button.
            obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Reconstruction run ', run_id, ' started.'];
            % While the rhythm is Not stated, the question once (never
            % headless; labelling only)
            rabbit_recording_rhythm.ask_once(obj.host);
            progress = obj.reconstruction_progress_open(run_id, 'Reconstruction run');
            progress_cleanup = onCleanup(@() obj.reconstruction_progress_close(progress));
            cb = @(st, st_status) obj.reconstruction_progress_stage(progress, run_id, st, st_status);
            [ok, err, failed_stage] = obj.reconstruction_tab.run_pipeline(run_id, ...
                struct('progress_cb', cb, ...
                'mesh_method', obj.ReconstructionMeshMethodDropDown.Value, ...
                'cloud_source', obj.ReconstructionCloudSourceDropDown.Value, ...
                'om_rows_flipped', obj.reconstruction_om_rows_flipped(), ...
                'view_numbering', obj.ReconstructionViewNumberingDropDown.Value, ...
                'activation_map', obj.host.processed_data.activation_map, ...
                'om_image', rabbit_rhythm_reproject.om_image_from_app(obj.host), ...
                'display_limits', rabbit_rhythm_reproject.app_display_limits(obj.host), ...
                'om_pose_frame', obj.ReconstructionOmPoseFrameDropDown.Value, ...
                'min_edge_edge', obj.ReconstructionEdgeWeightField.Value, ...
                'pacing_cycle_ms', obj.reconstruction_pacing_cycle_value(), ...
                'recording_rhythm', obj.reconstruction_recording_rhythm(), ...
                'activation_zero', rabbit_activation_zero.of(obj.host), ...
                'source_recording', obj.reconstruction_source_recording(), ...
                'source_recording_path', obj.reconstruction_source_recording_path(), ...
                'cv_map', obj.reconstruction_cv_map(), ...
                'cv_parameters', obj.reconstruction_cv_parameters(), ...
                'cv_pixel_um', obj.reconstruction_cv_pixel_um(), ...
                'cv_settings_record', obj.reconstruction_cv_settings_record(), ...
                'frames', frames, 'fps', fps, 'video_note', video_note, ...
                'activation_source', 'app.processed_data.activation_map (OM dataset; same heart as the reconstruction)', ...
                'analysis_parameters', struct('note', 'GUI defaults; deviations documented in the run manifest')));
            clear progress_cleanup;
            obj.cancel_pending_run_id = '';
            if ~ok
                if contains(err, 'STATE NOT CONFIRMED')
                    obj.unconfirmed_run_id = run_id;
                    obj.reconstruction_update_run_list();
                    obj.reconstruction_update_journey();
                    obj.reconstruction_update_enablement();
                    obj.ReconstructionResultsText.Value = { ...
                        sprintf('Run %s - STATE NOT CONFIRMED.', run_id), err, ...
                        'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                    obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Run ', run_id, ': state not confirmed.'];
                    uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction state not confirmed');
                    return;
                end
                obj.unconfirmed_run_id = '';
                [eff_st, ~] = obj.reconstruction_effective_status(run_id);
                if isempty(eff_st), eff_st = 'FAILED'; end
                obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Run ', run_id, ' ended: ', eff_st, ' (', char(failed_stage), ').'];
                obj.reconstruction_render_status(run_id, failed_stage);
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                if strcmp(eff_st, 'CANCELLED')
                    uialert(obj.host.opticalmappingUIFigure, ...
                        sprintf(['Run %s was cancelled. It cannot be confirmed that every helper program the step started has stopped; ' ...
                        'if the computer stays busy, check its running processes (e.g. Task Manager on Windows).'], run_id), ...
                        'Reconstruction run cancelled');
                else
                    cit = obj.reconstruction_tab.stage_citation_short(failed_stage);
                    if isempty(cit)
                        uialert(obj.host.opticalmappingUIFigure, obj.reconstruction_plain_message(err), 'Reconstruction run failed');
                    else
                        uialert(obj.host.opticalmappingUIFigure, sprintf('%s\n\nMethod: %s', obj.reconstruction_plain_message(err), cit), 'Reconstruction run failed');
                    end
                end
                obj.reconstruction_offer_attempt_cleanup(run_id);
                return;
            end
            obj.unconfirmed_run_id = '';
            obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Reconstruction run ', run_id, ' completed.'];
            obj.reconstruction_render_status(run_id);
            obj.reconstruction_update_run_list();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            obj.reconstruction_offer_attempt_cleanup(run_id);
        end
        function ReconstructionResumeButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('resume');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction resume');
                return;
            end
            % Push the field tool paths into the backend before any preflight
            [sync_ok, sync_err] = obj.reconstruction_sync_tool_paths();
            if ~sync_ok
                uialert(obj.host.opticalmappingUIFigure, sync_err, 'Reconstruction state');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('resume');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction resume');
                return;
            end
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Reconstruction');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to resume.', 'Reconstruction resume');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Reconstruction resume');
                return;
            end
            proj = obj.reconstruction_tab.reconstruction_stage_projection(run_id);
            if proj.is_running
                uialert(obj.host.opticalmappingUIFigure, ...
                    sprintf('Run %s is currently RUNNING; cannot resume an active run.', run_id), ...
                    'Reconstruction resume');
                return;
            end
            if isempty(proj.first_resumable_stage)
                uialert(obj.host.opticalmappingUIFigure, ...
                    sprintf('Run %s has no unfinished step to resume.', run_id), ...
                    'Reconstruction resume');
                return;
            end
            [mesh_method, cloud_source, go] = obj.reconstruction_resume_mesh_choice(run_id, proj.first_resumable_stage);
            if ~go
                return;
            end
            [ok, err] = obj.reconstruction_tab.resume_run(run_id);
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction resume');
                return;
            end
            next_stage = proj.first_resumable_stage;
            [state_ok, state_err] = obj.reconstruction_tab.commit_run_status(run_id, 'RUNNING');
            if ~state_ok
                obj.unconfirmed_run_id = run_id;
                obj.ReconstructionResultsText.Value = { ...
                    sprintf('Run %s - STATE NOT CONFIRMED.', run_id), state_err, ...
                    'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                uialert(obj.host.opticalmappingUIFigure, state_err, 'Reconstruction state not confirmed');
                return;
            end
            obj.unconfirmed_run_id = '';
            obj.reconstruction_render_status(run_id, next_stage);
            obj.reconstruction_update_run_list();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            drawnow;

            % While the rhythm is Not stated, the question once (never
            % headless; labelling only)
            rabbit_recording_rhythm.ask_once(obj.host);
            progress = obj.reconstruction_progress_open(run_id, 'Reconstruction resume');
            progress_cleanup = onCleanup(@() obj.reconstruction_progress_close(progress));
            cb = @(st, st_status) obj.reconstruction_progress_stage(progress, run_id, st, st_status);
            [ok, err, failed_stage] = obj.reconstruction_tab.run_pipeline(run_id, ...
                struct('progress_cb', cb, 'start_stage', next_stage, ...
                'mesh_method', mesh_method, 'cloud_source', cloud_source, ...
                'om_rows_flipped', obj.reconstruction_om_rows_flipped(), ...
                'view_numbering', obj.ReconstructionViewNumberingDropDown.Value, ...
                'activation_map', obj.host.processed_data.activation_map, ...
                'om_image', rabbit_rhythm_reproject.om_image_from_app(obj.host), ...
                'display_limits', rabbit_rhythm_reproject.app_display_limits(obj.host), ...
                'om_pose_frame', obj.ReconstructionOmPoseFrameDropDown.Value, ...
                'min_edge_edge', obj.ReconstructionEdgeWeightField.Value, ...
                'pacing_cycle_ms', obj.reconstruction_pacing_cycle_value(), ...
                'recording_rhythm', obj.reconstruction_recording_rhythm(), ...
                'activation_zero', rabbit_activation_zero.of(obj.host), ...
                'source_recording', obj.reconstruction_source_recording(), ...
                'source_recording_path', obj.reconstruction_source_recording_path(), ...
                'cv_map', obj.reconstruction_cv_map(), ...
                'cv_parameters', obj.reconstruction_cv_parameters(), ...
                'cv_pixel_um', obj.reconstruction_cv_pixel_um(), ...
                'cv_settings_record', obj.reconstruction_cv_settings_record(), ...
                'activation_source', 'app.processed_data.activation_map (OM dataset; same heart as the reconstruction)', ...
                'analysis_parameters', struct('note', 'GUI defaults; deviations documented in the run manifest')));
            clear progress_cleanup;
            obj.cancel_pending_run_id = '';
            if ~ok
                if contains(err, 'STATE NOT CONFIRMED')
                    obj.unconfirmed_run_id = run_id;
                    obj.reconstruction_update_run_list();
                    obj.reconstruction_update_journey();
                    obj.reconstruction_update_enablement();
                    obj.ReconstructionResultsText.Value = { ...
                        sprintf('Run %s - STATE NOT CONFIRMED.', run_id), err, ...
                        'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                    obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Run ', run_id, ': state not confirmed.'];
                    uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction state not confirmed');
                    return;
                end
                obj.unconfirmed_run_id = '';
                [eff_st, ~] = obj.reconstruction_effective_status(run_id);
                if isempty(eff_st), eff_st = 'FAILED'; end
                obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Run ', run_id, ' ended: ', eff_st, ' (', char(failed_stage), ').'];
                obj.reconstruction_render_status(run_id, failed_stage);
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                if strcmp(eff_st, 'CANCELLED')
                    uialert(obj.host.opticalmappingUIFigure, ...
                        sprintf(['Run %s was cancelled. It cannot be confirmed that every helper program the step started has stopped; ' ...
                        'if the computer stays busy, check its running processes (e.g. Task Manager on Windows).'], run_id), ...
                        'Reconstruction resume cancelled');
                else
                    cit = obj.reconstruction_tab.stage_citation_short(failed_stage);
                    if isempty(cit)
                        uialert(obj.host.opticalmappingUIFigure, obj.reconstruction_plain_message(err), 'Reconstruction run failed');
                    else
                        uialert(obj.host.opticalmappingUIFigure, sprintf('%s\n\nMethod: %s', obj.reconstruction_plain_message(err), cit), 'Reconstruction run failed');
                    end
                end
                obj.reconstruction_offer_attempt_cleanup(run_id);
                return;
            end
            obj.unconfirmed_run_id = '';
            obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Reconstruction run ', run_id, ' completed.'];
            obj.reconstruction_render_status(run_id);
            obj.reconstruction_update_run_list();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            obj.reconstruction_offer_attempt_cleanup(run_id);
        end
        function [status, durable] = reconstruction_cancel_status(obj, run_id)
            % Status for Cancel. A run on its way must stay cancellable even
            % if something else in its record does not pass the full check,
            % so only result.status of the record on disk decides here.
            [status, durable] = obj.reconstruction_effective_status(run_id);
            if ~durable || ~isempty(status), return; end
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', 'runs', run_id);
            names = {'manifest.v2.json', 'manifest.json'};
            for k = 1:2
                mp = fullfile(run_dir, names{k});
                if ~exist(mp, 'file'), continue; end
                try
                    mm = jsondecode(fileread(mp));
                    if isstruct(mm) && isscalar(mm) && isfield(mm, 'result') && ...
                            isstruct(mm.result) && isscalar(mm.result) && isfield(mm.result, 'status')
                        [ok, candidate] = obj.steps_run_status_text(mm.result.status);
                        if ok, status = candidate; end
                    end
                catch
                    status = '';
                end
                return;
            end
        end

        function ReconstructionCancelButtonPushed(obj, ~, ~)
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Reconstruction');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to cancel.', 'Reconstruction cancel');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            if isempty(run_id)
                % A selection whose run record is not valid is never a run
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, 'The selected run record is not valid; the view has been refreshed.', 'Reconstruction cancel');
                return;
            end
            obj.reconstruction_cancel_run(run_id);
        end

        function reconstruction_cancel_run(obj, run_id)
            % Cancel request for one run: the Cancel button passes the
            % selected run, the progress dialog the run it is driving.
            % Only after click-time liveness and durable-status revalidation:
            % the enablement repaint is not an authority, and a stale lock
            % can become uninspectable between paints.
            if obj.reconstruction_cancel_pending(run_id)
                obj.ReconstructionResultsText.Value = { ...
                    sprintf('Run %s status: CANCELLING.', run_id), ...
                    'Cancel was already requested. Waiting for the current step to stop.'};
                return;
            end
            if strcmp(obj.cancel_pending_run_id, run_id)
                obj.cancel_pending_run_id = '';
            end
            [eff_status, is_durable] = obj.reconstruction_cancel_status(run_id);
            if ~is_durable || ~strcmp(eff_status, 'RUNNING')
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                if ~is_durable || isempty(eff_status)
                    msg = sprintf('Run %s cannot be cancelled: its durable manifest is unreadable. The view has been refreshed.', run_id);
                else
                    msg = sprintf('Run %s is %s on disk, so it cannot be cancelled. The view has been refreshed.', run_id, eff_status);
                end
                uialert(obj.host.opticalmappingUIFigure, msg, 'Reconstruction cancel');
                return;
            end
            % RUNNING is destructive while the owner may still exist. Probe
            % the lock immediately before the status re-read and fail closed
            % when ownership cannot be inspected.
            [lock_state, ~, lock_message] = obj.reconstruction_lock_liveness(run_id);
            if strcmp(lock_state, 'UNAVAILABLE')
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                uialert(obj.host.opticalmappingUIFigure, ...
                    sprintf('Run %s cannot be cancelled safely: %s', run_id, lock_message), ...
                    'Reconstruction cancel');
                return;
            end
            % Re-read the durable manifest after liveness; only a RUNNING run
            % may reach request_cancel.
            [eff_status, is_durable] = obj.reconstruction_cancel_status(run_id);
            if ~is_durable || ~strcmp(eff_status, 'RUNNING')
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                uialert(obj.host.opticalmappingUIFigure, ...
                    sprintf('Run %s changed while cancellation was being checked; it was not cancelled.', run_id), ...
                    'Reconstruction cancel');
                return;
            end
            % With the owner gone a stop request would wait for ever: close
            % the run instead.
            if strcmp(lock_state, 'STALE') && ~obj.reconstruction_tab.pipeline_is_running(run_id)
                obj.reconstruction_close_interrupted_run(run_id);
                return;
            end
            [ok, err] = obj.reconstruction_tab.request_cancel(run_id);
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction cancel');
                return;
            end
            % A button click is only a transient request. The pipeline owns
            % the durable CANCELLED transition after run_stage records exit 130.
            obj.cancel_pending_run_id = run_id;
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            obj.ReconstructionResultsText.Value = { ...
                sprintf('Run %s status: CANCELLING.', run_id), ...
                'Cancel requested. Waiting for the current step to stop.' ...
            };
        end

        function tf = reconstruction_cancel_pending(obj, run_id)
            % A stop request is pending only while something can answer it.
            % A request to a run owned by another session outlives that
            % session if it dies, and the run would show CANCELLING for good.
            tf = ~isempty(run_id) && strcmp(obj.cancel_pending_run_id, run_id) && ...
                (obj.reconstruction_tab.pipeline_is_running(run_id) || ...
                ~strcmp(obj.reconstruction_lock_liveness(run_id), 'STALE'));
        end

        function reconstruction_close_interrupted_run(obj, run_id)
            % The owner of this RUNNING run has gone, so Cancel has nothing
            % to stop. The backend repeats every check before it writes.
            choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['Run %s is marked RUNNING, but the MATLAB ' ...
                'session running it has gone. Close it as INTERRUPTED? Finished steps are kept and Resume carries ' ...
                'on from the first unfinished step. %s'], run_id, obj.reconstruction_tab.unconfirmed_stop_note()), ...
                'Reconstruction run interrupted', 'Options', {'Close the run', 'Keep it'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Close the run')
                return;
            end
            [ok, err] = obj.reconstruction_tab.close_interrupted_run(run_id);
            if ~ok && contains(err, 'STATE NOT CONFIRMED')
                obj.unconfirmed_run_id = run_id;
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                obj.ReconstructionResultsText.Value = { ...
                    sprintf('Run %s - STATE NOT CONFIRMED.', run_id), err, ...
                    'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction state not confirmed');
                return;
            end
            obj.reconstruction_update_run_list();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction cancel');
                return;
            end
            obj.unconfirmed_run_id = '';
            obj.reconstruction_render_status(run_id);
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end
        function ReconstructionRefreshButtonPushed(obj, ~, ~)
            run_id = obj.reconstruction_selected_run_id();
            if ~isempty(run_id) && strcmp(obj.unconfirmed_run_id, run_id)
                [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
                m = obj.reconstruction_tab.read_manifest(fullfile(ds_root, [ds_stem '.matom'], ...
                    'reconstruction', 'runs', run_id));
                if ~isempty(m) && isfield(m, 'result') && isstruct(m.result) && ...
                        isfield(m.result, 'status')
                    [confirmed, ~] = obj.reconstruction_tab.confirm_run_status(run_id, m.result.status);
                    if ~confirmed && strcmp(char(m.result.status), 'INTERRUPTED')
                        % The tab-state half of a close failed: finish it
                        [confirmed, ~] = obj.reconstruction_tab.close_interrupted_run(run_id);
                    end
                    if confirmed
                        obj.unconfirmed_run_id = '';
                    end
                end
            end
            obj.reconstruction_update_run_list();
            run_id = obj.reconstruction_selected_run_id();
            if ~isempty(run_id)
                obj.reconstruction_render_status(run_id);
            end
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end
        % Button pushed function: ReconstructionCitationsButton
        function ReconstructionCitationsButtonPushed(obj, ~, ~)
            % Open the Help surface at the methods-and-citations topic.
            % Nothing is written to the results panel.
            obj.reconstruction_open_help('methods-and-citations', 'manual');
        end

        function reconstruction_show_log_window(obj)
            % The selected step's log, large and wrapped
            lines = obj.ReconstructionLogViewer.Value;
            if isempty(lines) || (iscell(lines) && all(cellfun(@isempty, lines)))
                lines = {'No log: choose a step in the list first.'};
            end
            scr = get(groot, 'ScreenSize');
            w = min(1100, scr(3) - 80);
            h = min(720, scr(4) - 120);
            fig = uifigure('Name', 'Step log', 'Position', [max(40, (scr(3) - w) / 2), max(60, (scr(4) - h) / 2), w, h]);
            gl = uigridlayout(fig, [1 1]);
            uitextarea(gl, 'Value', lines, 'Editable', 'off');   % a text area wraps its lines
        end

        function reconstruction_path_typed(obj)
            % A path typed into Reconstruction images or ROI file counts at
            % once, as a browsed one does
            obj.reconstruction_save_step2_inputs();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        % Button pushed function: ReconstructionImagesButton
        function ReconstructionImagesButtonPushed(obj, ~, ~)
            start = obj.ReconstructionImagesField.Value;
            if (isempty(start) || ~isfolder(start)) && ischar(obj.host.file_info.path) && isfolder(obj.host.file_info.path)
                start = obj.host.file_info.path;   % the recording's folder, where the cuts are
            end
            d = uigetdir(start, 'Select reconstruction images folder');
            if d ~= 0
                obj.ReconstructionImagesField.Value = d;
                obj.reconstruction_save_step2_inputs();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
            end
        end

        % Button pushed function: ReconstructionRoiButton
        function ReconstructionRoiButtonPushed(obj, ~, ~)
            % Select the saved rabbit-panoramic ROI JSON (rabbit_stack_io
            % v1 schema) that pins the canvas geometry for reprojection.
            start = '';
            if isfield(obj.host.file_info, 'path') && ~isempty(obj.host.file_info.path)
                start = obj.host.file_info.path;
            end
            [f, p] = uigetfile(fullfile(start, '*.json'), 'Regions file (written by the cut, or by the region editor)');
            if ~isequal(f, 0)
                obj.ReconstructionRoiField.Value = fullfile(p, f);
                obj.reconstruction_save_step2_inputs();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
            end
        end

        % Button pushed function: ReconstructionReprojectButton
        function ReconstructionReprojectButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('reproject');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Redo projection');
                return;
            end
            % Push the field tool paths into the backend
            % before any preflight, so the gate and the backend cannot
            % disagree about which executables will run.
            [sync_ok, sync_err] = obj.reconstruction_sync_tool_paths();
            if ~sync_ok
                uialert(obj.host.opticalmappingUIFigure, sync_err, 'Reconstruction state');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('reproject');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Redo projection');
                return;
            end
            % Run the reprojection step on the selected run: the RHYTHM
            % adapter projects the current activation map onto the run's
            % mesh with the undistorted cameras and the saved ROI JSON,
            % then reads the .cdf back. Method: RHYTHM (Gloschat et al.
            % 2018, Sci Rep 8:2921); lineage Laughner et al. 2012.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Reconstruction');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run first.', 'Redo projection');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Redo projection');
                return;
            end
            [ok, err] = obj.reconstruction_tab.resume_run(run_id);
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'Redo projection');
                return;
            end
            [ok, err, next_stage] = obj.reconstruction_tab.next_stage_to_run(run_id);
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'Redo projection');
                return;
            end
            % A COMPLETED run whose steps all passed can have its projection
            % redone, e.g. to add the OM video to a "Map only" run without a
            % new run. Nothing changes on disk until the
            % run is marked RUNNING below, so Cancel in either question
            % leaves the run COMPLETED with its projection as it was.
            redo = false;
            archive_rel = '';
            if isempty(next_stage)
                [redo, redo_why, archive_rel] = obj.reconstruction_tab.can_redo_reprojection(run_id);
                if ~redo
                    uialert(obj.host.opticalmappingUIFigure, sprintf(['Run %s has no pending projection step, ' ...
                        'and its projection cannot be redone: %s'], run_id, redo_why), 'Redo projection');
                    return;
                end
                choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['Redo the projection of run %s? ' ...
                    'The earlier projection is kept in %s. The sparse model, mesh and cameras are reused.'], ...
                    run_id, rabbit_reconstruction_tab.display_path(archive_rel)), 'Redo projection', ...
                    'Options', {'Redo projection', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
                if ~strcmp(choice, 'Redo projection')
                    return;
                end
            elseif ~strcmp(next_stage, 'reprojection')
                next_label = obj.reconstruction_stage_label(next_stage);
                uialert(obj.host.opticalmappingUIFigure, sprintf('Run %s has no pending projection step (next step: %s).', run_id, next_label), 'Redo projection');
                return;
            end
            % The OM frames shown now (current normalisation), on the same
            % canvas as the activation map, can be projected as a video too;
            % ask first, as Reproject from files does
            frames = [];
            fps = 1;
            video_note = '';
            try
                stack = obj.host.processed_data.image_stack{obj.host.display.normalisation};
            catch
                stack = [];
            end
            if isempty(stack)
                video_note = 'No OM frames are loaded, so only the activation map will be projected.';
            elseif ndims(stack) ~= 3 || size(stack, 1) ~= size(obj.host.processed_data.activation_map, 1) || ...
                    size(stack, 2) ~= size(obj.host.processed_data.activation_map, 2)
                video_note = sprintf(['The OM frames (%s) are not the same size as the activation map (%s), ' ...
                    'so only the activation map will be projected.'], mat2str(size(stack)), ...
                    mat2str(size(obj.host.processed_data.activation_map)));
            else
                choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['Also project the OM video ' ...
                    '(%d frames) onto the mesh? This takes longer than the activation map alone, ' ...
                    'and with the video the map keeps only the pixels that have data in every frame.'], ...
                    size(stack, 3)), 'Redo projection', ...
                    'Options', {'Map and video', 'Map only', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 3);
                if strcmp(choice, 'Cancel')
                    return;
                end
                if strcmp(choice, 'Map and video')
                    frames = stack;
                    fps = obj.host.data.fps;
                end
            end
            if ~isempty(video_note)
                choice = uiconfirm(obj.host.opticalmappingUIFigure, ['The OM video cannot be projected. ' video_note], ...
                    'Redo projection', 'Options', {'Map only', 'Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(choice, 'Cancel')
                    return;
                end
            end
            [state_ok, state_err] = obj.reconstruction_tab.commit_run_status(run_id, 'RUNNING');
            if ~state_ok
                obj.unconfirmed_run_id = run_id;
                obj.ReconstructionResultsText.Value = { ...
                    sprintf('Run %s - STATE NOT CONFIRMED.', run_id), state_err, ...
                    'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                uialert(obj.host.opticalmappingUIFigure, state_err, 'Reconstruction state not confirmed');
                return;
            end
            obj.unconfirmed_run_id = '';
            if redo
                % The run is RUNNING now: the earlier outputs/reprojection
                % moves to outputs/reprojection_NN and the step is pending
                [re_ok, re_err, archive_rel] = obj.reconstruction_tab.reopen_reprojection(run_id);
                if ~re_ok
                    % Nothing pending: back to COMPLETED; pending (the move
                    % went through, the check after it did not): FAILED,
                    % which Redo projection takes up again
                    [~, ~, ns_back] = obj.reconstruction_tab.next_stage_to_run(run_id);
                    if isempty(ns_back), back_status = 'COMPLETED'; else, back_status = 'FAILED'; end
                    [back_ok, back_err] = obj.reconstruction_tab.commit_run_status(run_id, back_status);
                    if ~back_ok
                        obj.unconfirmed_run_id = run_id;
                        re_err = sprintf('%s %s', re_err, back_err);
                    end
                    obj.reconstruction_update_run_list();
                    obj.reconstruction_update_journey();
                    obj.reconstruction_update_enablement();
                    uialert(obj.host.opticalmappingUIFigure, re_err, 'Redo projection');
                    return;
                end
            end
            obj.ReconstructionResultsText.Value = {sprintf('Run %s: projecting...', run_id)};
            obj.reconstruction_update_run_list();
            obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Redo projection of run ', run_id, ' started.'];
            % While the rhythm is Not stated, the question once (never
            % headless; labelling only)
            rabbit_recording_rhythm.ask_once(obj.host);
            progress = obj.reconstruction_progress_open(run_id, 'Redo projection');
            progress_cleanup = onCleanup(@() obj.reconstruction_progress_close(progress));
            cb = @(st, st_status) obj.reconstruction_progress_stage(progress, run_id, st, st_status);
            [ok, err, failed_stage] = obj.reconstruction_tab.run_pipeline(run_id, ...
                struct('progress_cb', cb, 'start_stage', 'reprojection', ...
                'activation_map', obj.host.processed_data.activation_map, ...
                'om_image', rabbit_rhythm_reproject.om_image_from_app(obj.host), ...
                'display_limits', rabbit_rhythm_reproject.app_display_limits(obj.host), ...
                'om_pose_frame', obj.ReconstructionOmPoseFrameDropDown.Value, ...
                'min_edge_edge', obj.ReconstructionEdgeWeightField.Value, ...
                'pacing_cycle_ms', obj.reconstruction_pacing_cycle_value(), ...
                'recording_rhythm', obj.reconstruction_recording_rhythm(), ...
                'activation_zero', rabbit_activation_zero.of(obj.host), ...
                'source_recording', obj.reconstruction_source_recording(), ...
                'source_recording_path', obj.reconstruction_source_recording_path(), ...
                'cv_map', obj.reconstruction_cv_map(), ...
                'cv_parameters', obj.reconstruction_cv_parameters(), ...
                'cv_pixel_um', obj.reconstruction_cv_pixel_um(), ...
                'cv_settings_record', obj.reconstruction_cv_settings_record(), ...
                'frames', frames, 'fps', fps, ...
                'om_rows_flipped', obj.reconstruction_om_rows_flipped(), ...
                'view_numbering', obj.ReconstructionViewNumberingDropDown.Value, ...
                'activation_state', obj.reconstruction_activation_restore_for(run_id), ...
                'activation_source', 'app.processed_data.activation_map (OM dataset; same heart as the reconstruction)', ...
                'analysis_parameters', struct('note', 'GUI defaults; deviations documented in the run manifest')));
            clear progress_cleanup;
            obj.cancel_pending_run_id = '';
            if ~ok && redo && ~isempty(archive_rel)
                err = sprintf('%s The earlier projection is kept in %s; Redo projection tries the projection again.', err, ...
                    rabbit_reconstruction_tab.display_path(archive_rel));
            end
            if ~ok
                if contains(err, 'STATE NOT CONFIRMED')
                    obj.unconfirmed_run_id = run_id;
                    obj.reconstruction_update_run_list();
                    obj.reconstruction_update_journey();
                    obj.reconstruction_update_enablement();
                    obj.ReconstructionResultsText.Value = { ...
                        sprintf('Run %s - STATE NOT CONFIRMED.', run_id), err, ...
                        'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
                    obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Run ', run_id, ': state not confirmed.'];
                    uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction state not confirmed');
                    return;
                end
                obj.unconfirmed_run_id = '';
                [eff_st, ~] = obj.reconstruction_effective_status(run_id);
                if isempty(eff_st), eff_st = 'FAILED'; end
                obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Run ', run_id, ' ended: ', eff_st, ' (', char(failed_stage), ').'];
                obj.reconstruction_render_status(run_id, failed_stage);
                obj.reconstruction_update_run_list();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                if strcmp(eff_st, 'CANCELLED')
                    uialert(obj.host.opticalmappingUIFigure, ...
                        sprintf(['Run %s was cancelled. It cannot be confirmed that every helper program the step started has stopped; ' ...
                        'if the computer stays busy, check its running processes (e.g. Task Manager on Windows).'], run_id), ...
                        'Redo projection cancelled');
                else
                    cit = obj.reconstruction_tab.stage_citation_short(failed_stage);
                    if isempty(cit)
                        uialert(obj.host.opticalmappingUIFigure, obj.reconstruction_plain_message(err), 'Reconstruction run failed');
                    else
                        uialert(obj.host.opticalmappingUIFigure, sprintf('%s\n\nMethod: %s', obj.reconstruction_plain_message(err), cit), 'Reconstruction run failed');
                    end
                end
                obj.reconstruction_offer_attempt_cleanup(run_id);
                return;
            end
            obj.reconstruction_tab.record_run(run_id, 'COMPLETED');
            obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ['Redo projection of run ', run_id, ' completed.'];
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            % Derive the run folder from the public dataset
            % field - the backend's run_dir_for is private and throws.
            [ds_root_r, ds_stem_r] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root_r, [ds_stem_r '.matom'], 'reconstruction', 'runs', run_id);
            % The Results box of the run as it is now (the new projection's
            % checks); the output paths are in Open run folder's tooltip
            obj.reconstruction_render_status(run_id);
            obj.ReconstructionResultsText.Value = [obj.ReconstructionResultsText.Value(:).', ...
                {'', sprintf('Projection done again (RHYTHM, Gloschat et al. 2018) into %s.', ...
                rabbit_reconstruction_tab.display_path(fullfile(run_dir, 'outputs', 'reprojection'), 60))}];
            % The folder cut from the left on screen, in full in the tooltip,
            % below the box's own tooltip (which it must not replace)
            obj.ReconstructionResultsText.Tooltip = [obj.reconstruction_results_tooltip(), ...
                {['Projection done again into ' rabbit_reconstruction_tab.display_path(fullfile(run_dir, 'outputs', 'reprojection'))]}];
            if redo && ~isempty(archive_rel)
                obj.ReconstructionResultsText.Value = [obj.ReconstructionResultsText.Value(:).', ...
                    {sprintf('The earlier projection is kept in %s.', rabbit_reconstruction_tab.display_path(archive_rel))}];
            end
            obj.reconstruction_offer_attempt_cleanup(run_id);
            obj.reconstruction_update_run_list();
        end

        % Button pushed function: ReconstructionVisualiseButton
        function ReconstructionVisualiseButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('visualise');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction visualisation');
                return;
            end
            % Visualise the selected run's artefacts
            % (pre-cleanup fused point cloud, post-cleanup/rebuilt
            % mesh, OM-reprojected activation mesh) with MATLAB-native
            % graphics. Paths are resolved from the run manifest, never
            % hardcoded; missing artefacts, malformed PLYs and
            % cancelled selection fail with a clear alert and never
            % mutate the source PLYs. Method citations:
            % COLMAP (Schoenberger & Frahm 2016, CVPR; Schoenberger et
            % al. 2016, ECCV); RHYTHM (Gloschat et al. 2018, Sci Rep
            % 8:2921, PMID 29440763).
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Reconstruction visualisation');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to visualise.', 'Reconstruction visualisation');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [ok, err, vis] = obj.reconstruction_tab.resolve_visualisation_context(run_id);
            if ~ok
                obj.VisualiseStatusText.Value = {['Visualisation blocked: ' err]};
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction visualisation');
                return;
            end
            [anom, anom_list] = obj.anomalous_views(vis);
            if anom
                msg = sprintf(['Not shown: %s changed after the run recorded it; ' ...
                    'the file may have been modified or replaced.'], anom_list);
                obj.VisualiseStatusText.Value = {msg};
                uialert(obj.host.opticalmappingUIFigure, msg, 'Reconstruction visualisation');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('visualise');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction visualisation');
                return;
            end
            obj.VisualiseFusedField.Value = vis.fused_ply;
            obj.VisualiseRebuiltField.Value = vis.rebuilt_ply;
            obj.VisualiseProjectedField.Value = vis.projected_ply;
            obj.VisualiseStatusText.Value = {sprintf('Loading the files of run %s...', run_id)};
            drawnow;
            [ok, err, fig] = obj.reconstruction_tab.visualise_artifacts(vis);
            if ~ok
                obj.VisualiseStatusText.Value = {sprintf('Visualisation failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction visualisation');
                return;
            end
            obj.VisualiseStatusText.Value = {sprintf('Run %s visualised (figure %d). Close the figure to dismiss.', run_id, fig.Number)};
        end

        % Button pushed function: ReconstructionTouchupPreviewButton
        function ReconstructionTouchupPreviewButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('touchup');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Mesh touch-up');
                return;
            end
            % Preview the touch-up operation on a copy of the selected
            % run's mesh. Nothing is written; the source PLY is never
            % mutated. The active source and the preview counts are
            % shown in the tab.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Mesh touch-up');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to touch up.', 'Mesh touch-up');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Mesh touch-up');
                return;
            end
            op_name = obj.TouchupOpDropDown.Value;
            if strcmp(op_name, 'Remove box')
                [box_ok, box, box_err] = obj.reconstruction_edit_parse_box(obj.TouchupBoxField.Value);
                if ~box_ok
                    uialert(obj.host.opticalmappingUIFigure, box_err, 'Mesh touch-up');
                    return;
                end
                ops = struct('op', 'remove_box', 'box', box);
            else
                ops = struct('op', 'remove_components', 'min_faces', obj.TouchupMinFacesField.Value);
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('touchup');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Mesh touch-up');
                return;
            end
            [ok, err, info] = obj.reconstruction_tab.touchup_preview(run_id, ops);
            if ~ok
                obj.TouchupStatusText.Value = {sprintf('Preview failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Mesh touch-up');
                return;
            end
            obj.TouchupSourceField.Value = info.source_ply;
            obj.reconstruction_edit_record_preview('touchup', run_id, ops, info);
            c = info.counts;
            obj.TouchupStatusText.Value = {sprintf( ...
                'Preview: %d -> %d faces (%d removed), %d -> %d vertices (%d removed), %d -> %d finite non-zero scalar entries (%d removed). Source unchanged.', ...
                c.n_faces_before, c.n_faces_after, c.n_faces_removed, ...
                c.n_vertices_before, c.n_vertices_after, c.n_vertices_removed, ...
                c.n_assigned_before, c.n_assigned_after, c.n_assigned_removed)};
        end

        % Button pushed function: ReconstructionTouchupApplyButton
        function ReconstructionTouchupApplyButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('touchup');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Mesh touch-up');
                return;
            end
            % Apply the touch-up to a copy: writes a new versioned PLY
            % under outputs/touchups/ and records the operation in the
            % run manifest (source hash, operations, parameters, counts,
            % timestamp). The source PLY is never overwritten.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Mesh touch-up');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to touch up.', 'Mesh touch-up');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Mesh touch-up');
                return;
            end
            op_name = obj.TouchupOpDropDown.Value;
            if strcmp(op_name, 'Remove box')
                [box_ok, box, box_err] = obj.reconstruction_edit_parse_box(obj.TouchupBoxField.Value);
                if ~box_ok
                    uialert(obj.host.opticalmappingUIFigure, box_err, 'Mesh touch-up');
                    return;
                end
                ops = struct('op', 'remove_box', 'box', box);
            else
                ops = struct('op', 'remove_components', 'min_faces', obj.TouchupMinFacesField.Value);
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('touchup');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Mesh touch-up');
                return;
            end
            [can_apply, apply_err] = obj.reconstruction_edit_can_apply('touchup', run_id, ops);
            if ~can_apply
                obj.TouchupStatusText.Value = {apply_err};
                uialert(obj.host.opticalmappingUIFigure, apply_err, 'Mesh touch-up');
                return;
            end
            try
                preview_info = obj.reconstruction_edit_pending_preview('touchup');
                [ok, err, rec] = obj.reconstruction_tab.touchup_apply(run_id, ops, preview_info);
            catch ME
                ok = false; err = ME.message; rec = struct();
            end
            if ~ok
                obj.reconstruction_edit_handle_apply_failure('touchup', run_id, err, ops);
                obj.TouchupStatusText.Value = {sprintf('Apply failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Mesh touch-up');
                return;
            end
            [commit_ok, commit_err] = obj.reconstruction_edit_verify_apply('touchup', run_id, rec, ops);
            if ~commit_ok
                obj.CopyOnWriteState.status = commit_err;
                obj.CopyOnWriteStatusLabel.Text = commit_err;
                obj.TouchupStatusText.Value = {commit_err};
                uialert(obj.host.opticalmappingUIFigure, commit_err, 'Mesh touch-up');
                return;
            end
            obj.reconstruction_edit_record_apply('touchup', run_id, rec, ops);
            obj.TouchupSourceField.Value = rec.source_ply;
            obj.TouchupOutputField.Value = rec.output_ply;
            c = rec.counts;
            obj.TouchupStatusText.Value = {sprintf( ...
                'Saved %s (%d faces, %d finite non-zero scalar entries; %d faces removed). Source unchanged.', ...
                rec.output_ply, c.n_faces_after, c.n_assigned_after, c.n_faces_removed)};
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        % Button pushed function: ReconstructionTouchupResetButton
        function ReconstructionTouchupResetButtonPushed(obj, ~, ~)
            % Cancel / reset: clear the touch-up operation fields and
            % status. No file is written or modified.
            obj.TouchupOpDropDown.Value = 'Remove box';
            obj.TouchupBoxField.Value = '';
            obj.TouchupMinFacesField.Value = 10;
            obj.reconstruction_edit_reset_operation('touchup');
            obj.reconstruction_edit_refresh();
            obj.TouchupSourceField.Value = obj.reconstruction_edit_source_field('touchup');
            obj.TouchupOutputField.Value = obj.reconstruction_edit_output_text('touchup');
            obj.TouchupStatusText.Value = {'Touch-up saves a new copy; the source file is never changed.'};
        end

        % Button pushed function: ReconstructionIntensityPreviewButton
        function ReconstructionIntensityPreviewButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('intensity');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Intensity filter');
                return;
            end
            % Preview the intensity filter on a copy of the selected
            % run's dense point set. Nothing is written; the source
            % PLY is never mutated. The active source and the preview
            % counts are shown in the tab.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Intensity filter');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to filter.', 'Intensity filter');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Intensity filter');
                return;
            end
            if strcmp(obj.IntensityModeDropDown.Value, 'Below threshold (keep >=)')
                mode = 'below';
            else
                mode = 'above';
            end
            op = struct('mode', mode, 'threshold', obj.IntensityThresholdField.Value);
            [gate_ok, gate_err] = obj.reconstruction_action_gate('intensity');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Intensity filter');
                return;
            end
            [ok, err, info] = obj.reconstruction_tab.intensity_preview(run_id, op);
            if ~ok
                obj.IntensityStatusText.Value = {sprintf('Preview failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Intensity filter');
                return;
            end
            obj.IntensitySourceField.Value = info.source_ply;
            obj.reconstruction_edit_record_preview('intensity', run_id, op, info);
            c = info.counts;
            obj.IntensityStatusText.Value = {sprintf( ...
                'Preview: %d -> %d points (%d removed), RGB luma/display proxy %s %d (min %.1f, max %.1f). Source unchanged.', ...
                c.n_vertices_before, c.n_vertices_after, c.n_vertices_removed, ...
                mode, op.threshold, c.luminance.min, c.luminance.max)};
        end

        % Button pushed function: ReconstructionIntensityApplyButton
        function ReconstructionIntensityApplyButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('intensity');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Intensity filter');
                return;
            end
            % Apply the intensity filter to a copy: writes a new
            % versioned PLY under outputs/intensity_filters/ + the
            % regenerated .vis + a manifest record (source hash,
            % operation, counts, luminance stats, .vis diagnostics,
            % timestamp). The source PLY is never overwritten.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Intensity filter');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to filter.', 'Intensity filter');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Intensity filter');
                return;
            end
            if strcmp(obj.IntensityModeDropDown.Value, 'Below threshold (keep >=)')
                mode = 'below';
            else
                mode = 'above';
            end
            op = struct('mode', mode, 'threshold', obj.IntensityThresholdField.Value);
            [gate_ok, gate_err] = obj.reconstruction_action_gate('intensity');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Intensity filter');
                return;
            end
            [can_apply, apply_err] = obj.reconstruction_edit_can_apply('intensity', run_id, op);
            if ~can_apply
                obj.IntensityStatusText.Value = {apply_err};
                uialert(obj.host.opticalmappingUIFigure, apply_err, 'Intensity filter');
                return;
            end
            try
                preview_info = obj.reconstruction_edit_pending_preview('intensity');
                [ok, err, rec] = obj.reconstruction_tab.intensity_apply(run_id, op, preview_info);
            catch ME
                ok = false; err = ME.message; rec = struct();
            end
            if ~ok
                obj.reconstruction_edit_handle_apply_failure('intensity', run_id, err, op);
                obj.IntensityStatusText.Value = {sprintf('Apply failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Intensity filter');
                return;
            end
            [commit_ok, commit_err] = obj.reconstruction_edit_verify_apply('intensity', run_id, rec, op);
            if ~commit_ok
                obj.CopyOnWriteState.status = commit_err;
                obj.CopyOnWriteStatusLabel.Text = commit_err;
                obj.IntensityStatusText.Value = {commit_err};
                uialert(obj.host.opticalmappingUIFigure, commit_err, 'Intensity filter');
                return;
            end
            obj.reconstruction_edit_record_apply('intensity', run_id, rec, op);
            obj.IntensitySourceField.Value = rec.source_ply;
            obj.IntensityOutputField.Value = rec.output_ply;
            c = rec.counts;
            vis_note = 'no .vis';
            if isfield(rec, 'vis') && isfield(rec.vis, 'regenerated')
                if rec.vis.regenerated
                    vis_note = '.vis regenerated';
                else
                    vis_note = rec.vis.diagnostics;
                end
            end
            obj.IntensityStatusText.Value = {sprintf( ...
                'Saved %s (%d points, %d removed; %s). Source unchanged.', ...
                rec.output_ply, c.n_vertices_after, c.n_vertices_removed, vis_note)};
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        % Button pushed function: ReconstructionIntensityResetButton
        function ReconstructionIntensityResetButtonPushed(obj, ~, ~)
            % Cancel / reset: clear the intensity-filter operation
            % fields and status. No file is written or modified.
            obj.IntensityModeDropDown.Value = 'Below threshold (keep >=)';
            obj.IntensityThresholdField.Value = 128;
            obj.reconstruction_edit_reset_operation('intensity');
            obj.reconstruction_edit_refresh();
            obj.IntensitySourceField.Value = obj.reconstruction_edit_source_field('intensity');
            obj.IntensityOutputField.Value = obj.reconstruction_edit_output_text('intensity');
            obj.IntensityStatusText.Value = {'Intensity filtering saves a new copy; the source file is never changed.'};
        end

        % Button pushed function: ReconstructionAreaSelectButton
        function ReconstructionAreaSelectButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('area_select');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, '2D area removal');
                return;
            end
            % Capture a camera + axes snapshot only after a valid ROI. A
            % cancelled/closed ROI is a no-write transition, never an error
            % that reaches Apply.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', '2D area removal');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to edit.', '2D area removal');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, '2D area removal');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('area_select');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, '2D area removal');
                return;
            end
            if ~usejava('desktop') && ~isdeployed
                obj.AreaStatusText.Value = {'Interactive selection is unavailable in headless mode.'};
                return;
            end
            [ok, err, fig, ax] = obj.reconstruction_tab.area_visualise_source(run_id);
            if ~ok
                obj.AreaStatusText.Value = {sprintf('Selection view failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, '2D area removal');
                return;
            end
            try, set(ax, 'Units', 'pixels'); catch, end
            [start_bind_ok, start_bind_err, start_desc] = obj.reconstruction_edit_descriptor('area', run_id, struct());
            if ~start_bind_ok
                try, close(fig); catch, end
                obj.AreaFigure = [];
                obj.AreaStatusText.Value = {sprintf('Selection failed: %s', start_bind_err)};
                return;
            end
            selection_axes_start = obj.reconstruction_edit_axes_identity(ax);
            selection_camera_start = struct('cp', get(ax, 'CameraPosition'), ...
                'ct', get(ax, 'CameraTarget'), 'cuv', get(ax, 'CameraUpVector'));
            obj.AreaFigure = fig;
            roi = [];
            selection_ok = false;
            try
                if strcmp(obj.AreaShapeDropDown.Value, 'Rectangle (drag)')
                    roi = drawrectangle(ax, 'Color', [0.85 0.1 0.1], 'LineWidth', 1.5);
                    shape = 'rect';
                else
                    roi = drawpolygon(ax, 'Color', [0.85 0.1 0.1], 'LineWidth', 1.5);
                    shape = 'lasso';
                end
                if isempty(roi) || ~isvalid(roi) || ~isgraphics(ax)
                    error('Reconstruction:SelectionCancelled', 'The selection was cancelled.');
                end
                position = roi.Position;
                if isempty(position) || any(~isfinite(position(:)))
                    error('Reconstruction:SelectionCancelled', 'The selection was cancelled.');
                end
                selection_axes_end = obj.reconstruction_edit_axes_identity(ax);
                selection_camera_end = struct('cp', get(ax, 'CameraPosition'), ...
                    'ct', get(ax, 'CameraTarget'), 'cuv', get(ax, 'CameraUpVector'));
                if ~isequaln(selection_axes_start, selection_axes_end) || ...
                        ~isequaln(selection_camera_start, selection_camera_end)
                    error('Reconstruction:ViewChanged', 'The view changed during the selection.');
                end
                op = struct('shape', shape, 'camera', selection_camera_start, ...
                    'axes_position', selection_axes_start.position, ...
                    'axes_identity', selection_axes_start);
                if strcmp(shape, 'rect')
                    op.rect = position;
                else
                    op.poly = position;
                end
                op.projection_identity = 'pinhole-normalized-camera-v2-screen-bound';
                selection_ok = true;
            catch
                selection_ok = false;
            end
            if ~selection_ok
                try, if ~isempty(roi) && isvalid(roi), delete(roi); end, catch, end
                try, if ~isempty(fig) && isgraphics(fig), close(fig); end, catch, end
                obj.AreaFigure = [];
                obj.AreaSelection = [];
                obj.reconstruction_edit_reset_operation('area');
                obj.AreaStatusText.Value = {'Selection cancelled - no output written.'};
                return;
            end
            [bind_ok, bind_err, bind_desc] = obj.reconstruction_edit_descriptor('area', run_id, op);
            if bind_ok && (~obj.reconstruction_edit_same_path(start_desc.path, bind_desc.path) || ...
                    ~strcmpi(char(start_desc.sha256), char(bind_desc.sha256)) || ...
                    ~strcmpi(char(start_desc.manifest_sha256), char(bind_desc.manifest_sha256)))
                bind_ok = false;
                bind_err = 'Source or active manifest changed during selection; reselect before Preview.';
            end
            if ~bind_ok
                obj.AreaSelection = [];
                obj.AreaStatusText.Value = {sprintf('Selection failed: %s', bind_err)};
                try, delete(roi); catch, end
                try, close(fig); catch, end
                obj.AreaFigure = [];
                return;
            end
            op.run_id = run_id;
            op.source_ply = start_desc.path;
            op.source_sha256 = start_desc.sha256;
            op.manifest_sha256 = start_desc.manifest_sha256;
            [okc, errc, info] = obj.reconstruction_tab.area_preview(run_id, op);
            if ~okc
                obj.AreaStatusText.Value = {sprintf('Selection failed: %s', errc)};
                uialert(obj.host.opticalmappingUIFigure, errc, '2D area removal');
                try, delete(roi); catch, end
                try, close(fig); catch, end
                obj.AreaFigure = [];
                return;
            end
            obj.AreaSelection = op;
            obj.AreaSourceField.Value = info.source_ply;
            obj.reconstruction_edit_record_preview('area', run_id, op, info);
            c = info.counts;
            obj.AreaStatusText.Value = {sprintf( ...
                'Selection: %d points in area (%d would remain). Preview or Apply to copy. Camera/axes snapshot captured; do not rotate the view after drawing.', ...
                c.n_selected, c.n_vertices_after)};
        end

        % Button pushed function: ReconstructionAreaPreviewButton
        function ReconstructionAreaPreviewButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('area');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, '2D area removal');
                return;
            end
            % Preview the 2D area removal on a copy of the current
            % point set. Nothing is written; the source PLY is never
            % mutated. The active source and the preview counts are
            % shown in the tab.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', '2D area removal');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to edit.', '2D area removal');
                return;
            end
            op = obj.AreaSelection;
            if isempty(obj.AreaSelection)
                obj.AreaStatusText.Value = {'Select an area first (Select area in 3D view).'};
                uialert(obj.host.opticalmappingUIFigure, 'Select an area first (Select area in 3D view).', '2D area removal');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, '2D area removal');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('area');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, '2D area removal');
                return;
            end
            if ~isstruct(obj.AreaSelection) || ~isfield(obj.AreaSelection, 'run_id') || ...
                    ~strcmp(obj.AreaSelection.run_id, run_id) || ...
                    ~obj.reconstruction_selection_source_matches('area', obj.AreaSelection, run_id)
                uialert(obj.host.opticalmappingUIFigure, 'The stored selection is stale or belongs to a different source; select it again.', '2D area removal');
                return;
            end
            [ok, err, info] = obj.reconstruction_tab.area_preview(run_id, obj.AreaSelection);
            if ~ok
                obj.reconstruction_edit_invalidate_preview_identity('area');
                obj.AreaStatusText.Value = {sprintf('Preview failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, '2D area removal');
                return;
            end
            obj.AreaSourceField.Value = info.source_ply;
            obj.reconstruction_edit_record_preview('area', run_id, obj.AreaSelection, info);
            c = info.counts;
            obj.AreaStatusText.Value = {sprintf( ...
                'Preview: %d -> %d points (%d removed, %d faces removed). Source unchanged.', ...
                c.n_vertices_before, c.n_vertices_after, c.n_vertices_removed, c.n_faces_removed)};
        end

        % Button pushed function: ReconstructionAreaApplyButton
        function ReconstructionAreaApplyButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('area');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, '2D area removal');
                return;
            end
            % Apply the 2D area removal to a copy: writes a new
            % versioned PLY under outputs/area_removals/ + the
            % regenerated .vis + a manifest record (source hash,
            % operation incl. camera, counts, .vis diagnostics,
            % timestamp). The source PLY is never overwritten.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', '2D area removal');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to edit.', '2D area removal');
                return;
            end
            op = obj.AreaSelection;
            if isempty(obj.AreaSelection)
                obj.AreaStatusText.Value = {'Select an area first (Select area in 3D view).'};
                uialert(obj.host.opticalmappingUIFigure, 'Select an area first (Select area in 3D view).', '2D area removal');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, '2D area removal');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('area');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, '2D area removal');
                return;
            end
            if ~isstruct(obj.AreaSelection) || ~isfield(obj.AreaSelection, 'run_id') || ...
                    ~strcmp(obj.AreaSelection.run_id, run_id) || ...
                    ~obj.reconstruction_selection_source_matches('area', obj.AreaSelection, run_id)
                uialert(obj.host.opticalmappingUIFigure, 'The stored selection is stale or belongs to a different source; select it again.', '2D area removal');
                return;
            end
            [can_apply, apply_err] = obj.reconstruction_edit_can_apply('area', run_id, obj.AreaSelection);
            if ~can_apply
                obj.AreaStatusText.Value = {apply_err};
                uialert(obj.host.opticalmappingUIFigure, apply_err, '2D area removal');
                return;
            end
            try
                preview_info = obj.reconstruction_edit_pending_preview('area');
                [ok, err, rec] = obj.reconstruction_tab.area_apply(run_id, obj.AreaSelection, preview_info);
            catch ME
                ok = false; err = ME.message; rec = struct();
            end
            if ~ok
                obj.reconstruction_edit_handle_apply_failure('area', run_id, err, op);
                obj.AreaStatusText.Value = {sprintf('Apply failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, '2D area removal');
                return;
            end
            [commit_ok, commit_err] = obj.reconstruction_edit_verify_apply('area', run_id, rec, op);
            if ~commit_ok
                obj.CopyOnWriteState.status = commit_err;
                obj.CopyOnWriteStatusLabel.Text = commit_err;
                obj.AreaStatusText.Value = {commit_err};
                uialert(obj.host.opticalmappingUIFigure, commit_err, '2D area removal');
                return;
            end
            obj.reconstruction_edit_record_apply('area', run_id, rec, op);
            obj.AreaSourceField.Value = rec.source_ply;
            obj.AreaOutputField.Value = rec.output_ply;
            c = rec.counts;
            vis_note = 'no .vis';
            if isfield(rec, 'vis') && isfield(rec.vis, 'regenerated')
                if rec.vis.regenerated
                    vis_note = '.vis regenerated';
                else
                    vis_note = rec.vis.diagnostics;
                end
            end
            obj.AreaStatusText.Value = {sprintf( ...
                'Saved %s (%d points, %d removed; %s). Source unchanged.', ...
                rec.output_ply, c.n_vertices_after, c.n_vertices_removed, vis_note)};
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        % Button pushed function: ReconstructionAreaResetButton
        function ReconstructionAreaResetButtonPushed(obj, ~, ~)
            % Cancel / reset: clear the 2D area-removal selection and
            % fields. No file is written or modified.
            obj.AreaSelection = [];
            if ~isempty(obj.AreaFigure) && isgraphics(obj.AreaFigure)
                close(obj.AreaFigure);
            end
            obj.AreaFigure = [];
            obj.reconstruction_edit_reset_operation('area');
            obj.reconstruction_edit_refresh();
            obj.AreaSourceField.Value = obj.reconstruction_edit_source_field('area');
            obj.AreaOutputField.Value = obj.reconstruction_edit_output_text('area');
            obj.AreaStatusText.Value = {'Area removal saves a new copy; the source file is never changed.'};
        end

        % Button pushed function: ReconstructionSmoothSelectButton
        function ReconstructionSmoothSelectButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('smooth_select');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Bounded smoothing');
                return;
            end
            % Capture a camera + axes snapshot only after a valid brush click.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Bounded smoothing');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to edit.', 'Bounded smoothing');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Bounded smoothing');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('smooth_select');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Bounded smoothing');
                return;
            end
            if ~usejava('desktop') && ~isdeployed
                obj.SmoothStatusText.Value = {'Interactive selection is unavailable in headless mode.'};
                return;
            end
            [ok, err, fig, ax] = obj.reconstruction_tab.smooth_visualise_source(run_id);
            if ~ok
                obj.SmoothStatusText.Value = {sprintf('Selection view failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Bounded smoothing');
                return;
            end
            try, set(ax, 'Units', 'pixels'); catch, end
            [start_bind_ok, start_bind_err, start_desc] = obj.reconstruction_edit_descriptor('smooth', run_id, struct());
            if ~start_bind_ok
                try, close(fig); catch, end
                obj.SmoothFigure = [];
                obj.SmoothStatusText.Value = {sprintf('Selection failed: %s', start_bind_err)};
                return;
            end
            selection_axes_start = obj.reconstruction_edit_axes_identity(ax);
            selection_camera_start = struct('cp', get(ax, 'CameraPosition'), ...
                'ct', get(ax, 'CameraTarget'), 'cuv', get(ax, 'CameraUpVector'));
            obj.SmoothFigure = fig;
            selection_ok = false;
            try
                figure(fig);
                [click_x, click_y] = ginput(1);
                if isempty(click_x) || isempty(click_y) || ...
                        any(~isfinite([click_x(1) click_y(1)])) || ...
                        ~isgraphics(fig) || ~isgraphics(ax)
                    error('Reconstruction:SelectionCancelled', 'The selection was cancelled.');
                end
                ray = get(ax, 'CurrentPoint');
                center = ray(1, :);
                selection_axes_end = obj.reconstruction_edit_axes_identity(ax);
                selection_camera_end = struct('cp', get(ax, 'CameraPosition'), ...
                    'ct', get(ax, 'CameraTarget'), 'cuv', get(ax, 'CameraUpVector'));
                if ~isequaln(selection_axes_start, selection_axes_end) || ...
                        ~isequaln(selection_camera_start, selection_camera_end)
                    error('Reconstruction:ViewChanged', 'The view changed during the selection.');
                end
                op = struct('center', center, ...
                    'radius_px', obj.SmoothRadiusField.Value, ...
                    'iterations', obj.SmoothIterationsField.Value, ...
                    'strength', obj.SmoothStrengthField.Value, ...
                    'camera', selection_camera_start, ...
                    'axes_position', selection_axes_start.position, ...
                    'axes_identity', selection_axes_start, ...
                    'axpos', selection_axes_start.position, ...
                    'projection_identity', 'pinhole-normalized-camera-v2-screen-bound');
                selection_ok = true;
            catch
                selection_ok = false;
            end
            if ~selection_ok
                try, if ~isempty(fig) && isgraphics(fig), close(fig); end, catch, end
                obj.SmoothFigure = [];
                obj.SmoothSelection = [];
                obj.reconstruction_edit_reset_operation('smooth');
                obj.SmoothStatusText.Value = {'Selection cancelled - no output written.'};
                return;
            end
            [bind_ok, bind_err, bind_desc] = obj.reconstruction_edit_descriptor('smooth', run_id, op);
            if bind_ok && (~obj.reconstruction_edit_same_path(start_desc.path, bind_desc.path) || ...
                    ~strcmpi(char(start_desc.sha256), char(bind_desc.sha256)) || ...
                    ~strcmpi(char(start_desc.manifest_sha256), char(bind_desc.manifest_sha256)))
                bind_ok = false;
                bind_err = 'Source or active manifest changed during selection; reselect before Preview.';
            end
            if ~bind_ok
                obj.SmoothSelection = [];
                obj.SmoothStatusText.Value = {sprintf('Selection failed: %s', bind_err)};
                try, close(fig); catch, end
                obj.SmoothFigure = [];
                return;
            end
            op.run_id = run_id;
            op.source_ply = start_desc.path;
            op.source_sha256 = start_desc.sha256;
            op.manifest_sha256 = start_desc.manifest_sha256;
            [okc, errc, info] = obj.reconstruction_tab.smooth_preview(run_id, op);
            if ~okc
                obj.SmoothStatusText.Value = {sprintf('Selection failed: %s', errc)};
                uialert(obj.host.opticalmappingUIFigure, errc, 'Bounded smoothing');
                try, close(fig); catch, end
                obj.SmoothFigure = [];
                return;
            end
            obj.SmoothSelection = op;
            obj.SmoothSourceField.Value = info.source_ply;
            obj.reconstruction_edit_record_preview('smooth', run_id, op, info);
            c = info.counts;
            obj.SmoothStatusText.Value = {sprintf( ...
                'Brush: %d vertices in circle (%d pinned boundary, %d to smooth). Preview or Apply to copy. Camera/axes snapshot captured; do not rotate the view after clicking.', ...
                c.n_in_brush, c.n_pinned, c.n_moved)};
        end

        % Button pushed function: ReconstructionSmoothPreviewButton
        function ReconstructionSmoothPreviewButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('smooth');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Bounded smoothing');
                return;
            end
            % Preview the bounded smoothing on a copy of the current
            % mesh. Nothing is written; the source PLY is never
            % mutated. The active source and the preview counts are
            % shown in the tab.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Bounded smoothing');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to edit.', 'Bounded smoothing');
                return;
            end
            op = obj.SmoothSelection;
            if isempty(obj.SmoothSelection)
                obj.SmoothStatusText.Value = {'Select a brush centre first (Select brush centre in 3D view).'};
                uialert(obj.host.opticalmappingUIFigure, 'Select a brush centre first (Select brush centre in 3D view).', 'Bounded smoothing');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Bounded smoothing');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('smooth');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Bounded smoothing');
                return;
            end
            if ~isstruct(obj.SmoothSelection) || ~isfield(obj.SmoothSelection, 'run_id') || ...
                    ~strcmp(obj.SmoothSelection.run_id, run_id) || ...
                    ~obj.reconstruction_selection_source_matches('smooth', obj.SmoothSelection, run_id)
                uialert(obj.host.opticalmappingUIFigure, 'The stored selection is stale or belongs to a different source; select it again.', 'Bounded smoothing');
                return;
            end
            [ok, err, info] = obj.reconstruction_tab.smooth_preview(run_id, obj.SmoothSelection);
            if ~ok
                obj.reconstruction_edit_invalidate_preview_identity('smooth');
                obj.SmoothStatusText.Value = {sprintf('Preview failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Bounded smoothing');
                return;
            end
            obj.SmoothSourceField.Value = info.source_ply;
            obj.reconstruction_edit_record_preview('smooth', run_id, obj.SmoothSelection, info);
            c = info.counts;
            % The displacement is in the mesh's own units (mm or model units)
            obj.SmoothStatusText.Value = {sprintf( ...
                'Preview: %d vertices smoothed (%d pinned, max displacement %.3g %s). Source unchanged.', ...
                c.n_moved, c.n_pinned, c.max_displacement, ...
                obj.reconstruction_tab.run_units(obj.reconstruction_selected_run_dir()))};
        end

        % Button pushed function: ReconstructionSmoothApplyButton
        function ReconstructionSmoothApplyButtonPushed(obj, ~, ~)
            [gate_ok, gate_err] = obj.reconstruction_action_gate('smooth');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Bounded smoothing');
                return;
            end
            % Apply the bounded smoothing to a copy: writes a new
            % versioned PLY under outputs/smoothings/ + the
            % regenerated .vis + a manifest record (source hash,
            % operation incl. camera, counts, .vis diagnostics,
            % timestamp). The source PLY is never overwritten.
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Bounded smoothing');
                return;
            end
            if isempty(obj.ReconstructionRunList.Value)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run to edit.', 'Bounded smoothing');
                return;
            end
            op = obj.SmoothSelection;
            if isempty(obj.SmoothSelection)
                obj.SmoothStatusText.Value = {'Select a brush centre first (Select brush centre in 3D view).'};
                uialert(obj.host.opticalmappingUIFigure, 'Select a brush centre first (Select brush centre in 3D view).', 'Bounded smoothing');
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            [prov_ok, prov_err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ~prov_ok
                uialert(obj.host.opticalmappingUIFigure, prov_err, 'Bounded smoothing');
                return;
            end
            [gate_ok, gate_err] = obj.reconstruction_action_gate('smooth');
            if ~gate_ok
                obj.reconstruction_safe_refresh();
                uialert(obj.host.opticalmappingUIFigure, gate_err, 'Bounded smoothing');
                return;
            end
            if ~isstruct(obj.SmoothSelection) || ~isfield(obj.SmoothSelection, 'run_id') || ...
                    ~strcmp(obj.SmoothSelection.run_id, run_id) || ...
                    ~obj.reconstruction_selection_source_matches('smooth', obj.SmoothSelection, run_id)
                uialert(obj.host.opticalmappingUIFigure, 'The stored selection is stale or belongs to a different source; select it again.', 'Bounded smoothing');
                return;
            end
            [can_apply, apply_err] = obj.reconstruction_edit_can_apply('smooth', run_id, obj.SmoothSelection);
            if ~can_apply
                obj.SmoothStatusText.Value = {apply_err};
                uialert(obj.host.opticalmappingUIFigure, apply_err, 'Bounded smoothing');
                return;
            end
            try
                preview_info = obj.reconstruction_edit_pending_preview('smooth');
                [ok, err, rec] = obj.reconstruction_tab.smooth_apply(run_id, obj.SmoothSelection, preview_info);
            catch ME
                ok = false; err = ME.message; rec = struct();
            end
            if ~ok
                obj.reconstruction_edit_handle_apply_failure('smooth', run_id, err, op);
                obj.SmoothStatusText.Value = {sprintf('Apply failed: %s', err)};
                uialert(obj.host.opticalmappingUIFigure, err, 'Bounded smoothing');
                return;
            end
            [commit_ok, commit_err] = obj.reconstruction_edit_verify_apply('smooth', run_id, rec, op);
            if ~commit_ok
                obj.CopyOnWriteState.status = commit_err;
                obj.CopyOnWriteStatusLabel.Text = commit_err;
                obj.SmoothStatusText.Value = {commit_err};
                uialert(obj.host.opticalmappingUIFigure, commit_err, 'Bounded smoothing');
                return;
            end
            obj.reconstruction_edit_record_apply('smooth', run_id, rec, op);
            obj.SmoothSourceField.Value = rec.source_ply;
            obj.SmoothOutputField.Value = rec.output_ply;
            c = rec.counts;
            vis_note = 'no .vis';
            if isfield(rec, 'vis') && isfield(rec.vis, 'regenerated')
                if rec.vis.regenerated
                    vis_note = '.vis regenerated';
                else
                    vis_note = rec.vis.diagnostics;
                end
            end
            obj.SmoothStatusText.Value = {sprintf( ...
                'Saved %s (%d vertices smoothed, max displacement %.3g %s; %s). Source unchanged.', ...
                rec.output_ply, c.n_moved, c.max_displacement, ...
                obj.reconstruction_tab.run_units(obj.reconstruction_selected_run_dir()), vis_note)};
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        % Button pushed function: ReconstructionSmoothResetButton
        function ReconstructionSmoothResetButtonPushed(obj, ~, ~)
            % Cancel / reset: clear the smoothing selection and
            % fields. No file is written or modified.
            obj.SmoothSelection = [];
            if ~isempty(obj.SmoothFigure) && isgraphics(obj.SmoothFigure)
                close(obj.SmoothFigure);
            end
            obj.SmoothFigure = [];
            obj.reconstruction_edit_reset_operation('smooth');
            obj.reconstruction_edit_refresh();
            obj.SmoothSourceField.Value = obj.reconstruction_edit_source_field('smooth');
            obj.SmoothOutputField.Value = obj.reconstruction_edit_output_text('smooth');
            obj.SmoothStatusText.Value = {'Smoothing saves a new copy; the source file is never changed.'};
        end

        % Button pushed function: ReconstructionSparseButton
        function ReconstructionSparseButtonPushed(obj, ~, ~)
            d = uigetdir(obj.ReconstructionSparseField.Value, 'Select COLMAP sparse model folder');
            if d ~= 0
                obj.ReconstructionSparseField.Value = d;
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
            end
        end

        % Value changed function: tool-path edit fields
        function ReconstructionToolPathChanged(obj, ~, ~)
            % Persist tool-path edits into the tab-state JSON, and keep a
            % changed path for this session and as the last used path
            % (MATLAB preferences).
            % Spaces, tabs and line breaks at either end of a pasted path
            % are dropped ("python.exe<TAB>")
            try
                tf_ = obj.reconstruction_tool_fields();
                for k_ = 1:size(tf_, 1)
                    v_ = obj.(tf_{k_, 2}).Value;
                    if ischar(v_) && ~strcmp(v_, strtrim(v_))
                        obj.(tf_{k_, 2}).Value = strtrim(v_);
                    end
                end
            catch
            end
            obj.reconstruction_note_typed_tool_paths();
            if isempty(obj.reconstruction_tab), return; end
            % Persist only after scalar state and text validation: a
            % malformed tool_paths would make set_tool_path throw
            % MATLAB:structAssToNonStruct. An empty field is valid text: it
            % clears a path, and the COLMAP models folder is optional.
            try, obj.reconstruction_update_journey(); catch, end
            try
                [state_ok, state_message] = obj.reconstruction_tool_state_valid();
                if ~state_ok
                    uialert(obj.host.opticalmappingUIFigure, state_message, 'Reconstruction tool path');
                    return;
                end
                fields = obj.reconstruction_tool_fields();
                vals = cell(size(fields, 1), 1);
                for k = 1:size(fields, 1)
                    raw = obj.(fields{k, 2}).Value;
                    if ischar(raw) && (isrow(raw) || isempty(raw))
                        vals{k} = raw;
                    elseif isstring(raw) && isscalar(raw) && ~ismissing(raw)
                        vals{k} = char(raw);
                    else
                        uialert(obj.host.opticalmappingUIFigure, 'Tool paths must be scalar text values.', 'Reconstruction tool path');
                        return;
                    end
                end
                for k = 1:size(fields, 1)
                    obj.reconstruction_tab.set_tool_path(fields{k, 1}, vals{k});
                end
            catch err
                uialert(obj.host.opticalmappingUIFigure, ['Tool paths could not be saved: ' err.message], 'Reconstruction tool path');
                return;
            end
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        % Helper: refresh the tab after a dataset is loaded
%% Reconstruction tab helper methods
% The guided steps of the tab (numbered sections and the journey strip).
% They show the backend's state only: no reconstruction numbers or PLY
% files are changed here. Notes for editing (MATLAB R2026a):
%   * uilabel and uibutton have no .Value, only .Text.
%   * .Tooltip takes a char or a cellstr.
%   * Step-header buttons are wired as @(src, ev) fn(app, src, ev); a plain
%     @fn handle cannot reach a classdef method.
%   * Gated controls are written as app.<Control>.<Prop> statements, as the
%     tests read this code to find them.

        function reconstruction_edit_reset_state(obj)
            %EDIT_RESET_STATE Reset only the shared presentation state.
            %No source, output or manifest file is touched.
            obj.CopyOnWritePending = struct('operation', {}, 'run_id', {}, ...
                'source_path', {}, 'source_sha256', {}, 'parameters', {}, ...
                'preview_info', {}, ...
                'parameters_sha256', {}, 'view_identity', {}, ...
                'manifest_sha256', {}, 'output_snapshot', {}, 'valid', {});
            obj.CopyOnWriteApplied = struct('operation', {}, 'run_id', {}, ...
                'selected_run_id', {}, 'output_path', {}, 'output_sha256', {}, 'manifest_path', {}, ...
                'record_id', {}, 'source_sha256', {});
            obj.CopyOnWriteState = struct('selected_run_id', '', 'run_root', '', ...
                'sources', struct(), 'status', 'No run selected');
            obj.reconstruction_edit_clear_interactive();
        end

        function reconstruction_edit_clear_interactive(obj)
            % Clear selections and close their figures after a run/source
            % refresh or Apply. No source, output or manifest is touched.
            if isprop(obj, 'AreaSelection'), obj.AreaSelection = []; end
            if isprop(obj, 'SmoothSelection'), obj.SmoothSelection = []; end
            try
                if isprop(obj, 'AreaFigure') && ~isempty(obj.AreaFigure) && isgraphics(obj.AreaFigure)
                    close(obj.AreaFigure);
                end
            catch
            end
            try
                if isprop(obj, 'SmoothFigure') && ~isempty(obj.SmoothFigure) && isgraphics(obj.SmoothFigure)
                    close(obj.SmoothFigure);
                end
            catch
            end
            if isprop(obj, 'AreaFigure'), obj.AreaFigure = []; end
            if isprop(obj, 'SmoothFigure'), obj.SmoothFigure = []; end
        end

        function reconstruction_edit_refresh(obj)
            %EDIT_REFRESH Refresh source descriptors and invalidate any token
            %whose run, source digest, manifest or admissibility changed.
            if ~isprop(obj, 'CopyOnWritePanel')
                return;
            end
            if isempty(obj.CopyOnWriteState) || ~isstruct(obj.CopyOnWriteState) || ...
                    ~isfield(obj.CopyOnWriteState, 'status')
                obj.reconstruction_edit_reset_state();
            end
            previous_run_id = '';
            if isstruct(obj.CopyOnWriteState) && isfield(obj.CopyOnWriteState, 'selected_run_id')
                previous_run_id = obj.CopyOnWriteState.selected_run_id;
            end
            run_id = '';
            if ~isempty(obj.reconstruction_tab) && isprop(obj, 'ReconstructionRunList')
                run_id = obj.reconstruction_selected_run_id();
            end
            if ~strcmp(char(previous_run_id), char(run_id))
                obj.CopyOnWriteApplied = struct('operation', {}, 'run_id', {}, ...
                    'selected_run_id', {}, 'output_path', {}, 'output_sha256', {}, 'manifest_path', {}, ...
                    'record_id', {}, 'source_sha256', {});
                obj.reconstruction_edit_clear_interactive();
            end
            sources = struct();
            names = {'touchup', 'intensity', 'area', 'smooth'};
            for k = 1:numel(names)
                d = obj.reconstruction_edit_empty_descriptor(names{k});
                if isempty(run_id) || isempty(obj.reconstruction_tab)
                    d.reason = 'No run selected.';
                else
                    try
                        [ok, err, d0] = obj.reconstruction_tab.edit_source_descriptor(run_id, names{k});
                        if isstruct(d0), d = d0; end
                        if ~ok && isempty(d.reason), d.reason = err; end
                    catch ME
                        d.reason = sprintf('Source resolver unavailable: %s.', ME.message);
                    end
                end
                sources.(names{k}) = d;
            end
            obj.CopyOnWriteState.selected_run_id = run_id;
            if isempty(run_id)
                obj.CopyOnWriteState.run_root = '';
                obj.CopyOnWriteState.status = 'No run selected. Select a run to use these tools.';
            else
                d = sources.touchup;
                obj.CopyOnWriteState.run_root = d.run_dir;
                obj.CopyOnWriteState.status = 'Run selected - inspect an operation source or Preview before Apply.';
            end
            obj.CopyOnWriteState.sources = sources;
            obj.reconstruction_edit_invalidate_changed(sources, run_id);
            % A refresh first validates pending tokens against fresh source,
            % manifest and output-chain descriptors, then restores only the
            % still-valid captured Area/Smoothing identity into shared state.
            obj.reconstruction_edit_restore_preview_identities(run_id);
            obj.TouchupSourceField.Value = obj.reconstruction_edit_source_field('touchup');
            obj.IntensitySourceField.Value = obj.reconstruction_edit_source_field('intensity');
            obj.AreaSourceField.Value = obj.reconstruction_edit_source_field('area');
            obj.SmoothSourceField.Value = obj.reconstruction_edit_source_field('smooth');
            obj.TouchupOutputField.Value = obj.reconstruction_edit_output_text('touchup');
            obj.IntensityOutputField.Value = obj.reconstruction_edit_output_text('intensity');
            obj.AreaOutputField.Value = obj.reconstruction_edit_output_text('area');
            obj.SmoothOutputField.Value = obj.reconstruction_edit_output_text('smooth');
            obj.CopyOnWriteSummaryLabel.Text = obj.reconstruction_edit_summary(sources, run_id);
            obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
        end

        function d = reconstruction_edit_empty_descriptor(obj, operation) %#ok<INUSD>
            d = struct('operation', char(operation), 'run_id', '', 'run_dir', '', ...
                'source_class', '', 'path', '', 'relative_path', '', ...
                'exists', false, 'parseable', false, 'admissible', false, ...
                'sha256', '', 'manifest_path', '', 'manifest_sha256', '', ...
                'reason', 'No run selected.', 'view_identity', struct());
        end

        function txt = reconstruction_edit_source_field(obj, operation)
            txt = 'Source unavailable: No run selected.';
            if isempty(obj.CopyOnWriteState) || ~isstruct(obj.CopyOnWriteState) || ...
                    ~isfield(obj.CopyOnWriteState, 'sources') || ...
                    ~isfield(obj.CopyOnWriteState.sources, operation)
                return;
            end
            d = obj.CopyOnWriteState.sources.(operation);
            if isfield(d, 'admissible') && d.admissible
                txt = sprintf('Source (%s): %s', d.source_class, d.relative_path);
            elseif isfield(d, 'reason') && ~isempty(d.reason)
                txt = ['Source unavailable: ' d.reason];
            end
        end

        function txt = reconstruction_edit_summary(obj, sources, run_id) %#ok<INUSD>
            if isempty(run_id)
                first = 'Selected run: No run selected.';
            else
                root = sources.touchup.run_dir;
                first = sprintf('Selected run: %s (folder: %s).', run_id, root);
            end
            lines = {first};
            names = {'touchup', 'intensity', 'area', 'smooth'};
            labels = {'Touch-up', 'Intensity', 'Area', 'Smoothing'};
            for k = 1:numel(names)
                d = sources.(names{k});
                if isfield(d, 'admissible') && d.admissible
                    line = sprintf('%s - source: %s (%s).', ...
                        labels{k}, d.relative_path, d.source_class);
                else
                    reason = 'unavailable';
                    if isfield(d, 'reason') && ~isempty(d.reason), reason = d.reason; end
                    line = sprintf('%s - no source available: %s.', labels{k}, regexprep(reason, '\.$', ''));
                end
                if any(strcmp(names{k}, {'area', 'smooth'}))
                    % The camera/axes identity stays in the preview record;
                    % the user only needs to know the view is remembered.
                    if isfield(d, 'view_identity') && isstruct(d.view_identity) && ...
                            isfield(d.view_identity, 'camera_bound') && d.view_identity.camera_bound
                        view_text = 'The 3-D view used for the selection is remembered for Apply.';
                    else
                        view_text = 'The 3-D view is remembered when you make the selection.';
                    end
                    line = sprintf('%s %s', line, view_text);
                end
                lines{end+1} = line; %#ok<AGROW>
            end
            txt = strjoin(lines, newline);
        end

        function reconstruction_edit_invalidate_changed(obj, sources, run_id)
            % Invalidate on run switch, manifest/source refresh, digest drift,
            % or loss of operation admissibility. Stored Area/Smoothing
            % selections are cleared as soon as their bound source is stale,
            % even when no pending token remains.
            selection_stale = false;
            if ~isempty(obj.AreaSelection)
                selection_stale = ~isfield(sources, 'area') || ...
                    ~obj.reconstruction_edit_selection_matches(obj.AreaSelection, sources.area, run_id);
            end
            if ~isempty(obj.SmoothSelection)
                selection_stale = selection_stale || ~isfield(sources, 'smooth') || ...
                    ~obj.reconstruction_edit_selection_matches(obj.SmoothSelection, sources.smooth, run_id);
            end
            if selection_stale
                obj.reconstruction_edit_clear_interactive();
                obj.CopyOnWriteState.status = 'Selection stale - reselect before Preview.';
            end
            if isempty(obj.CopyOnWritePending) || ~isstruct(obj.CopyOnWritePending)
                obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
                return;
            end
            for k = 1:numel(obj.CopyOnWritePending)
                p = obj.CopyOnWritePending(k);
                stale = ~isfield(p, 'valid') || ~p.valid || ...
                    ~strcmp(p.run_id, run_id);
                if ~stale && isfield(sources, p.operation)
                    d = sources.(p.operation);
                    stale = ~d.admissible || ~obj.reconstruction_edit_same_path(d.path, p.source_path) || ...
                        ~strcmpi(d.sha256, p.source_sha256) || ...
                        ~strcmp(obj.reconstruction_edit_manifest_hash(d.run_dir), p.manifest_sha256) || ...
                        ~obj.reconstruction_edit_same_snapshot(obj.reconstruction_edit_output_snapshot(d.run_dir), p.output_snapshot);
                end
                if stale
                    obj.CopyOnWritePending(k).valid = false;
                    if isfield(obj.CopyOnWriteState, 'sources') && ...
                            isfield(obj.CopyOnWriteState.sources, p.operation)
                        obj.CopyOnWriteState.sources.(p.operation).view_identity = struct();
                    end
                    obj.CopyOnWriteState.status = 'Settings changed since Preview. Preview again.';
                end
            end
            obj.reconstruction_edit_render_shared_summary();
            if isempty(run_id)
                obj.CopyOnWriteState.status = 'No run selected. Select a run to use these tools.';
            end
            obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
        end

        function tf = reconstruction_edit_selection_matches(obj, selection, d, run_id)
            tf = isstruct(selection) && numel(selection) == 1 && ...
                isfield(selection, 'run_id') && strcmp(char(selection.run_id), char(run_id)) && ...
                isfield(selection, 'source_ply') && isfield(selection, 'source_sha256') && ...
                isfield(selection, 'manifest_sha256') && isstruct(d) && ...
                isfield(d, 'admissible') && d.admissible && ...
                obj.reconstruction_edit_same_path(selection.source_ply, d.path) && ...
                strcmpi(char(selection.source_sha256), char(d.sha256)) && ...
                strcmpi(char(selection.manifest_sha256), char(d.manifest_sha256));
        end

        function [ok, err, d] = reconstruction_edit_descriptor(obj, operation, run_id, parameters)
            ok = false; err = ''; d = obj.reconstruction_edit_empty_descriptor(operation);
            if nargin < 4 || isempty(parameters), parameters = struct(); end
            if isempty(obj.reconstruction_tab)
                err = 'No reconstruction run is selected.';
                d.reason = err;
                return;
            end
            [ok, err, d] = obj.reconstruction_tab.edit_source_descriptor(run_id, operation, parameters);
            if ~ok && isempty(d.reason), d.reason = err; end
        end

        function reconstruction_edit_record_preview(obj, operation, run_id, parameters, info)
            % Record a matching in-memory candidate. This call is read-only
            % with respect to source PLY, manifest and prior derived outputs.
            [ok, err, d] = obj.reconstruction_edit_descriptor(operation, run_id, parameters);
            if ~ok
                obj.reconstruction_edit_invalidate_preview_identity(operation);
                obj.CopyOnWriteState.status = ['Preview failed: ' err];
                obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
                return;
            end
            if isfield(info, 'source_ply') && ~obj.reconstruction_edit_same_path(info.source_ply, d.path)
                obj.reconstruction_edit_invalidate_preview_identity(operation);
                obj.CopyOnWriteState.status = 'Settings changed since Preview. Preview again.';
                obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
                return;
            end
            info.edit_run_id = run_id;
            info.edit_manifest_sha256 = obj.reconstruction_edit_manifest_hash(d.run_dir);
            token = struct();
            token.operation = operation; token.run_id = run_id;
            token.source_path = d.path; token.source_sha256 = d.sha256;
            token.parameters = parameters;
            token.parameters_sha256 = obj.reconstruction_edit_digest_text(jsonencode(parameters));
            token.preview_info = info;
            token.view_identity = obj.reconstruction_edit_view_identity(operation, parameters);
            token.manifest_sha256 = obj.reconstruction_edit_manifest_hash(d.run_dir);
            token.output_snapshot = obj.reconstruction_edit_output_snapshot(d.run_dir);
            token.valid = true;
            obj.reconstruction_edit_upsert_pending(token);
            obj.reconstruction_edit_publish_preview_identity(token);
            obj.CopyOnWriteState.status = sprintf('Preview available (not written) - %s.', operation);
            obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
        end

        function reconstruction_edit_publish_preview_identity(obj, token)
            if ~any(strcmp(token.operation, {'area', 'smooth'})) || ...
                    ~isfield(token, 'valid') || ~token.valid
                return;
            end
            if ~isfield(obj.CopyOnWriteState, 'sources') || ...
                    ~isfield(obj.CopyOnWriteState.sources, token.operation)
                d = obj.reconstruction_edit_empty_descriptor(token.operation);
                d.run_id = token.run_id;
                d.path = token.source_path;
                d.sha256 = token.source_sha256;
                obj.CopyOnWriteState.sources.(token.operation) = d;
            end
            obj.CopyOnWriteState.sources.(token.operation).view_identity = token.view_identity;
            obj.reconstruction_edit_render_shared_summary();
        end

        function reconstruction_edit_invalidate_preview_identity(obj, operation)
            for k = 1:numel(obj.CopyOnWritePending)
                if strcmp(obj.CopyOnWritePending(k).operation, operation)
                    obj.CopyOnWritePending(k).valid = false;
                end
            end
            if isfield(obj.CopyOnWriteState, 'sources') && ...
                    isfield(obj.CopyOnWriteState.sources, operation)
                obj.CopyOnWriteState.sources.(operation).view_identity = struct();
            end
            obj.reconstruction_edit_render_shared_summary();
        end

        function reconstruction_edit_restore_preview_identities(obj, run_id)
            for k = 1:numel(obj.CopyOnWritePending)
                token = obj.CopyOnWritePending(k);
                if isfield(token, 'valid') && token.valid && ...
                        strcmp(char(token.run_id), char(run_id))
                    obj.reconstruction_edit_publish_preview_identity(token);
                end
            end
        end

        function reconstruction_edit_render_shared_summary(obj)
            if ~isprop(obj, 'CopyOnWriteSummaryLabel') || ...
                    ~isfield(obj.CopyOnWriteState, 'sources')
                return;
            end
            run_id = '';
            if isfield(obj.CopyOnWriteState, 'selected_run_id')
                run_id = obj.CopyOnWriteState.selected_run_id;
            end
            names = {'touchup', 'intensity', 'area', 'smooth'};
            for k = 1:numel(names)
                if ~isfield(obj.CopyOnWriteState.sources, names{k})
                    obj.CopyOnWriteState.sources.(names{k}) = ...
                        obj.reconstruction_edit_empty_descriptor(names{k});
                end
            end
            obj.CopyOnWriteSummaryLabel.Text = obj.reconstruction_edit_summary( ...
                obj.CopyOnWriteState.sources, run_id);
        end

        function view = reconstruction_edit_view_identity(obj, operation, parameters) %#ok<INUSD>
            view = struct('kind', 'not_applicable', 'camera', struct(), ...
                'camera_bound', false, 'axes_id', '', 'axes_units', '', ...
                'projection_identity', '', 'axes_identity', struct());
            if any(strcmp(operation, {'area', 'smooth'}))
                view.kind = 'aggregate_3d_reconstruction_view';
                view.projection_identity = 'pinhole-normalized-camera-v2-screen-bound';
                if isstruct(parameters)
                    if isfield(parameters, 'camera') && isstruct(parameters.camera) && ...
                            isfield(parameters.camera, 'cp') && isfield(parameters.camera, 'ct') && ...
                            isfield(parameters.camera, 'cuv') && numel(parameters.camera.cp) == 3 && ...
                            numel(parameters.camera.ct) == 3 && numel(parameters.camera.cuv) == 3 && ...
                            all(isfinite(parameters.camera.cp)) && all(isfinite(parameters.camera.ct)) && ...
                            all(isfinite(parameters.camera.cuv))
                        view.camera = parameters.camera;
                        view.camera_bound = true;
                    end
                    if isfield(parameters, 'axes_identity') && isstruct(parameters.axes_identity)
                        view.axes_identity = parameters.axes_identity;
                        if isfield(parameters.axes_identity, 'id')
                            view.axes_id = parameters.axes_identity.id;
                        end
                        if isfield(parameters.axes_identity, 'units')
                            view.axes_units = char(parameters.axes_identity.units);
                        end
                    elseif isfield(parameters, 'axes_position')
                        view.axes_identity = struct('position', parameters.axes_position);
                        view.axes_id = mat2str(parameters.axes_position);
                    elseif isfield(parameters, 'axpos')
                        view.axes_identity = struct('position', parameters.axpos);
                        view.axes_id = mat2str(parameters.axpos);
                    end
                end
            end
        end

        function id = reconstruction_edit_axes_identity(obj, ax) %#ok<INUSD>
            id = struct('id', '', 'tag', '', 'units', '', 'position', [], ...
                'figure_position', [], 'limits', [], 'projection', '', ...
                'camera_view_angle', [], 'camera_view_angle_mode', '', ...
                'data_aspect_ratio', [], 'data_aspect_ratio_mode', '', ...
                'plot_box_aspect_ratio', [], 'plot_box_aspect_ratio_mode', '', ...
                'outer_position', [], 'tight_inset', []);
            try
                id.tag = char(get(ax, 'Tag'));
                id.units = char(get(ax, 'Units'));
                id.position = double(get(ax, 'Position'));
                id.limits = [double(get(ax, 'XLim')); double(get(ax, 'YLim')); double(get(ax, 'ZLim'))];
                id.projection = char(get(ax, 'Projection'));
                id.camera_view_angle = double(get(ax, 'CameraViewAngle'));
                id.camera_view_angle_mode = char(get(ax, 'CameraViewAngleMode'));
                id.data_aspect_ratio = double(get(ax, 'DataAspectRatio'));
                id.data_aspect_ratio_mode = char(get(ax, 'DataAspectRatioMode'));
                id.plot_box_aspect_ratio = double(get(ax, 'PlotBoxAspectRatio'));
                id.plot_box_aspect_ratio_mode = char(get(ax, 'PlotBoxAspectRatioMode'));
                id.outer_position = double(get(ax, 'OuterPosition'));
                id.tight_inset = double(get(ax, 'TightInset'));
                fig = ancestor(ax, 'figure');
                if ~isempty(fig) && isgraphics(fig)
                    id.figure_position = double(get(fig, 'Position'));
                end
                tag = id.tag;
                if isempty(tag), tag = 'untagged'; end
                id.id = sprintf('axes:%s:%s:%s:%s:%s', tag, id.units, ...
                    mat2str(id.position), id.projection, mat2str(id.camera_view_angle));
            catch
                id = struct('id', '', 'tag', '', 'units', '', 'position', [], ...
                    'figure_position', [], 'limits', [], 'projection', '', ...
                    'camera_view_angle', [], 'camera_view_angle_mode', '', ...
                    'data_aspect_ratio', [], 'data_aspect_ratio_mode', '', ...
                    'plot_box_aspect_ratio', [], 'plot_box_aspect_ratio_mode', '', ...
                    'outer_position', [], 'tight_inset', []);
            end
        end

        function reconstruction_edit_upsert_pending(obj, token)
            if isempty(obj.CopyOnWritePending)
                obj.CopyOnWritePending = token;
                return;
            end
            idx = 0;
            for k = 1:numel(obj.CopyOnWritePending)
                if strcmp(obj.CopyOnWritePending(k).operation, token.operation), idx = k; end
            end
            if idx == 0
                obj.CopyOnWritePending(end+1) = token;
            else
                obj.CopyOnWritePending(idx) = token;
            end
        end

        function info = reconstruction_edit_pending_preview(obj, operation)
            info = struct();
            for k = 1:numel(obj.CopyOnWritePending)
                if strcmp(obj.CopyOnWritePending(k).operation, operation) && ...
                        isfield(obj.CopyOnWritePending(k), 'preview_info')
                    info = obj.CopyOnWritePending(k).preview_info;
                    return;
                end
            end
        end

        function [ok, err] = reconstruction_edit_can_apply(obj, operation, run_id, parameters)
            ok = false; err = 'Preview required.';
            idx = 0;
            for k = 1:numel(obj.CopyOnWritePending)
                if strcmp(obj.CopyOnWritePending(k).operation, operation), idx = k; end
            end
            if idx == 0 || ~obj.CopyOnWritePending(idx).valid
                err = 'Preview required - run Preview before Apply to copy.';
                obj.CopyOnWriteState.status = err;
                obj.CopyOnWriteStatusLabel.Text = err;
                return;
            end
            p = obj.CopyOnWritePending(idx);
            if ~strcmp(p.run_id, run_id)
                err = 'The selected run changed since Preview. Preview again.';
            elseif ~strcmp(p.parameters_sha256, obj.reconstruction_edit_digest_text(jsonencode(parameters)))
                err = 'Settings changed since Preview. Preview again.';
            else
                [desc_ok, desc_err, d] = obj.reconstruction_edit_descriptor(operation, run_id, parameters);
                if ~desc_ok || ~obj.reconstruction_edit_same_path(d.path, p.source_path) || ...
                        ~strcmpi(d.sha256, p.source_sha256)
                    err = 'The source file changed since Preview. Preview again.';
                elseif ~isequaln(p.view_identity, obj.reconstruction_edit_view_identity(operation, parameters))
                    err = 'The view changed since Preview. Preview again.';
                elseif ~strcmp(obj.reconstruction_edit_manifest_hash(d.run_dir), p.manifest_sha256)
                    err = 'The run record or the source changed since Preview. Preview again.';
                elseif ~obj.reconstruction_edit_same_snapshot(obj.reconstruction_edit_output_snapshot(d.run_dir), p.output_snapshot)
                    err = 'An earlier saved copy changed since Preview. Preview again.';
                else
                    ok = true;
                    return;
                end
            end
            obj.CopyOnWritePending(idx).valid = false;
            obj.reconstruction_edit_invalidate_preview_identity(operation);
            obj.CopyOnWriteState.status = err;
            obj.CopyOnWriteStatusLabel.Text = err;
        end

        function [ok, err] = reconstruction_edit_verify_apply(obj, operation, run_id, rec, parameters)
            % Verify output bytes, source identity, canonical containment,
            % admissible PLY read-back and the exact active-manifest record
            % before publishing Applied to copy.
            if nargin < 5 || isempty(parameters), parameters = struct(); end
            ok = false; err = 'Save not confirmed: the saved copy could not be checked. Look in the run folder before trying again.';
            if isempty(rec) || ~isstruct(rec) || ~isfield(rec, 'id') || ...
                    ~isfield(rec, 'run_id') || ~strcmp(char(rec.run_id), char(run_id)) || ...
                    ~isfield(rec, 'output_ply') || ~isfield(rec, 'output_sha256') || ...
                    ~isfield(rec, 'source_ply') || ~isfield(rec, 'source_sha256') || ...
                    ~isfield(rec, 'manifest_path')
                return;
            end
            [desc_ok, desc_err, d] = obj.reconstruction_edit_descriptor(operation, run_id, parameters);
            if ~desc_ok || isempty(d.run_dir)
                err = ['Save not confirmed: the source could not be found (' desc_err '). Look in the run folder before trying again.'];
                return;
            end
            run_dir = d.run_dir;
            if isempty(obj.CopyOnWriteState.run_root) || ...
                    ~obj.reconstruction_edit_same_path(obj.CopyOnWriteState.run_root, run_dir)
                err = 'Save not confirmed: a different run is now selected. Look in the run folder before trying again.';
                return;
            end
            if ~obj.reconstruction_edit_path_in_run(rec.output_ply, run_dir) || ...
                    ~obj.reconstruction_edit_path_in_run(rec.source_ply, run_dir)
                err = 'Save not confirmed: the saved copy is outside the selected run folder. Look in the run folder before trying again.';
                return;
            end
            if exist(rec.output_ply, 'file') ~= 2
                err = 'Save not confirmed: the saved copy is missing. Look in the run folder before trying again.';
                return;
            end
            [hash_ok, out_hash] = obj.reconstruction_edit_hash_file(rec.output_ply);
            if ~hash_ok || ~strcmpi(out_hash, rec.output_sha256)
                err = 'Save not confirmed: the saved copy could not be read back. Look in the run folder before trying again.';
                return;
            end
            if ~strcmpi(d.sha256, rec.source_sha256) || ...
                    ~obj.reconstruction_edit_same_path(d.path, rec.source_ply)
                err = 'Save not confirmed: the source file changed. Look in the run folder before trying again.';
                return;
            end
            [ply_ok, ~, ~] = obj.reconstruction_tab.load_visualisation_ply(rec.output_ply);
            if ~ply_ok
                err = 'Save not confirmed: the saved copy could not be read as a PLY file. Look in the run folder before trying again.';
                return;
            end
            m = obj.reconstruction_tab.read_manifest(run_dir);
            if isempty(m) || ~isstruct(m) || ~isfield(m, 'run_id') || ...
                    ~strcmp(char(m.run_id), char(run_id))
                err = 'Save not confirmed: the run record does not match the selected run. Look in the run folder before trying again.';
                return;
            end
            field = obj.reconstruction_edit_manifest_field(operation);
            if ~isfield(m, field) || isempty(m.(field)), return; end
            records = m.(field);
            expected_field = obj.reconstruction_edit_manifest_field(operation);
            collection_ok = strcmp(field, expected_field);
            for k = numel(records):-1:1
                r = records(k);
                if strcmp(operation, 'touchup')
                    operation_ok = isfield(r, 'operations') && isfield(rec, 'operations') && ...
                        isequaln(r.operations, rec.operations) && isequaln(rec.operations, parameters);
                else
                    operation_ok = isfield(r, 'operation') && isstruct(rec.operation) && ...
                        isequaln(r.operation, rec.operation) && isequaln(rec.operation, parameters);
                end
                run_ok = isfield(r, 'run_id') && strcmp(char(r.run_id), char(run_id));
                id_ok = isfield(r, 'id') && strcmp(char(r.id), char(rec.id));
                if collection_ok && operation_ok && run_ok && id_ok && ...
                        isfield(r, 'output_ply') && isfield(r, 'output_sha256') && ...
                        isfield(r, 'source_ply') && isfield(r, 'source_sha256') && ...
                        isfield(r, 'manifest_path') && ...
                        obj.reconstruction_edit_same_path(obj.reconstruction_edit_rebase_path(r.manifest_path, run_dir), d.manifest_path) && ...
                        obj.reconstruction_edit_same_path(r.output_ply, rec.output_ply) && ...
                        ~isempty(regexp(char(r.output_sha256), '^[0-9a-fA-F]{64}$', 'once')) && ...
                        strcmpi(char(r.output_sha256), char(rec.output_sha256)) && ...
                        obj.reconstruction_edit_same_path(r.source_ply, rec.source_ply) && ...
                        ~isempty(regexp(char(r.source_sha256), '^[0-9a-fA-F]{64}$', 'once')) && ...
                        strcmpi(char(r.source_sha256), char(rec.source_sha256)) && ...
                        obj.reconstruction_edit_verify_vis_record(operation, rec, r, run_dir)
                    ok = true;
                    return;
                end
            end
        end

        function tf = reconstruction_edit_verify_vis_record(obj, operation, rec, recorded, run_dir)
            tf = true;
            if strcmp(operation, 'touchup')
                return;
            end
            if ~isfield(rec, 'vis') || ~isstruct(rec.vis) || ...
                    ~isfield(recorded, 'vis') || ~isequaln(rec.vis, recorded.vis)
                tf = false;
                return;
            end
            v = rec.vis;
            if ~isfield(v, 'regenerated') || ~islogical(v.regenerated) || numel(v.regenerated) ~= 1
                tf = false;
                return;
            end
            if v.regenerated
                if ~isfield(v, 'output_vis') || ~isfield(v, 'source_vis') || ...
                        ~obj.reconstruction_edit_path_in_run(v.output_vis, run_dir) || ...
                        ~obj.reconstruction_edit_path_in_run(v.source_vis, run_dir) || ...
                        exist(v.output_vis, 'file') ~= 2 || exist(v.source_vis, 'file') ~= 2
                    tf = false;
                    return;
                end
                [out_ok, out_hash] = obj.reconstruction_edit_hash_file(v.output_vis);
                [src_ok, src_hash] = obj.reconstruction_edit_hash_file(v.source_vis);
                tf = out_ok && src_ok && ~isempty(out_hash) && ~isempty(src_hash) && ...
                    isfield(v, 'semantic_verified') && islogical(v.semantic_verified) && ...
                    isscalar(v.semantic_verified) && v.semantic_verified && ...
                    isfield(v, 'source_sha256') && isfield(v, 'output_sha256') && ...
                    strcmpi(char(v.source_sha256), char(src_hash)) && ...
                    strcmpi(char(v.output_sha256), char(out_hash));
            else
                tf = isfield(v, 'diagnostics') && ~isempty(char(v.diagnostics));
            end
        end

        function reconstruction_edit_record_apply(obj, operation, run_id, rec, parameters)
            if nargin < 5 || isempty(parameters), parameters = struct(); end
            [~, ~, d] = obj.reconstruction_edit_descriptor(operation, run_id, parameters);
            p = struct('operation', operation, 'run_id', run_id, ...
                'selected_run_id', run_id, 'output_path', rec.output_ply, 'output_sha256', rec.output_sha256, ...
                'manifest_path', d.manifest_path, ...
                'record_id', rec.id, 'source_sha256', rec.source_sha256);
            if isempty(obj.CopyOnWriteApplied)
                obj.CopyOnWriteApplied = p;
            else
                obj.CopyOnWriteApplied(end+1) = p;
            end
            obj.CopyOnWritePending = obj.CopyOnWritePending( ...
                ~strcmp({obj.CopyOnWritePending.operation}, operation));
            obj.reconstruction_edit_clear_interactive();
            obj.reconstruction_edit_refresh();
            vis_note = 'no .vis record';
            if isfield(rec, 'vis') && isstruct(rec.vis) && isfield(rec.vis, 'regenerated')
                if rec.vis.regenerated
                    vis_note = '.vis regenerated';
                else
                    diag = char(rec.vis.diagnostics);
                    if isempty(diag), diag = 'source .vis unavailable'; end
                    vis_note = ['.vis unavailable: ' diag];
                end
            end
            obj.CopyOnWriteState.status = sprintf('Saved as a copy - %s; the new file and the run record were checked after saving; %s.', operation, vis_note);
            obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
        end

        function reconstruction_edit_handle_apply_failure(obj, operation, run_id, err, parameters)
            if nargin < 5 || isempty(parameters), parameters = struct(); end
            if obj.reconstruction_edit_no_commit_verified(operation, run_id, parameters)
                obj.CopyOnWriteState.status = 'Failed (no output committed).';
            else
                obj.CopyOnWriteState.status = 'Save not confirmed: the saved copy could not be checked. Look in the run folder before trying again.';
            end
            obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
            if nargin > 3 && isempty(err), obj.CopyOnWriteState.status = obj.CopyOnWriteState.status; end
        end

        function tf = reconstruction_edit_no_commit_verified(obj, operation, run_id, parameters)
            if nargin < 4 || isempty(parameters), parameters = struct(); end
            tf = false;
            idx = 0;
            for k = 1:numel(obj.CopyOnWritePending)
                if strcmp(obj.CopyOnWritePending(k).operation, operation), idx = k; end
            end
            if idx == 0, return; end
            p = obj.CopyOnWritePending(idx);
            if ~strcmp(p.run_id, run_id), return; end
            [~, ~, d] = obj.reconstruction_edit_descriptor(operation, run_id, parameters);
            if isempty(d.run_dir), return; end
            current_manifest = obj.reconstruction_edit_manifest_hash(d.run_dir);
            current_snapshot = obj.reconstruction_edit_output_snapshot(d.run_dir);
            tf = strcmp(current_manifest, p.manifest_sha256) && ...
                obj.reconstruction_edit_same_snapshot(current_snapshot, p.output_snapshot);
        end

        function reconstruction_edit_reset_operation(obj, operation)
            % Reset clears pending state only; the current run's last-applied
            % output remains visible. Any captured Preview identity is stale.
            obj.reconstruction_edit_invalidate_preview_identity(operation);
            selected_run = '';
            if isstruct(obj.CopyOnWriteState) && isfield(obj.CopyOnWriteState, 'selected_run_id')
                selected_run = obj.CopyOnWriteState.selected_run_id;
            end
            retained = false;
            for k = 1:numel(obj.CopyOnWriteApplied)
                if strcmp(obj.CopyOnWriteApplied(k).operation, operation) && ...
                        strcmp(char(obj.CopyOnWriteApplied(k).run_id), char(selected_run))
                    retained = true;
                    break;
                end
            end
            if ~retained
                obj.CopyOnWriteState.status = 'Reset complete - no applied output is recorded for this run.';
            else
                obj.CopyOnWriteState.status = sprintf('Reset complete - applied output retained (%s).', operation);
            end
            obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
        end

        function txt = reconstruction_edit_output_text(obj, operation)
            txt = 'Output: -';
            selected_run = '';
            if isstruct(obj.CopyOnWriteState) && isfield(obj.CopyOnWriteState, 'selected_run_id')
                selected_run = obj.CopyOnWriteState.selected_run_id;
            end
            if isempty(selected_run), return; end
            for k = numel(obj.CopyOnWriteApplied):-1:1
                if strcmp(obj.CopyOnWriteApplied(k).operation, operation) && ...
                        strcmp(char(obj.CopyOnWriteApplied(k).run_id), char(selected_run))
                    txt = ['Output: ' obj.CopyOnWriteApplied(k).output_path];
                    return;
                end
            end
        end

        function ReconstructionEditControlChanged(obj, src, ~)
            names = {'TouchupOpDropDown', 'TouchupBoxField', 'TouchupMinFacesField'};
            operation = '';
            for k = 1:numel(names)
                if isequal(src, obj.(names{k})), operation = 'touchup'; end
            end
            names = {'IntensityModeDropDown', 'IntensityThresholdField'};
            for k = 1:numel(names)
                if isequal(src, obj.(names{k})), operation = 'intensity'; end
            end
            names = {'AreaShapeDropDown'};
            for k = 1:numel(names)
                if isequal(src, obj.(names{k})), operation = 'area'; end
            end
            names = {'SmoothRadiusField', 'SmoothIterationsField', 'SmoothStrengthField'};
            for k = 1:numel(names)
                if isequal(src, obj.(names{k})), operation = 'smooth'; end
            end
            if ~isempty(operation)
                for k = 1:numel(obj.CopyOnWritePending)
                    if strcmp(obj.CopyOnWritePending(k).operation, operation)
                        obj.CopyOnWritePending(k).valid = false;
                    end
                end
                if strcmp(operation, 'area')
                    obj.AreaSelection = [];
                elseif strcmp(operation, 'smooth')
                    obj.SmoothSelection = [];
                end
                obj.CopyOnWriteState.status = sprintf('%s settings changed. Select again, then Preview.', operation);
                obj.CopyOnWriteStatusLabel.Text = obj.CopyOnWriteState.status;
            end
        end

        function [ok, box, err] = reconstruction_edit_parse_box(obj, raw) %#ok<INUSD>
            % Non-evaluating parser: exactly six finite numeric tokens with
            % strict ordered bounds. str2double never evaluates expressions.
            ok = false; box = []; err = '';
            if isstring(raw), raw = char(raw); end
            if ~ischar(raw)
                err = 'Enter the box as 6 finite numbers: xlo xhi ylo yhi zlo zhi (in the run''s units).';
                return;
            end
            raw = strtrim(raw);
            if isempty(raw)
                err = 'Enter the box as 6 finite numbers: xlo xhi ylo yhi zlo zhi (in the run''s units).';
                return;
            end
            tokens = regexp(raw, '[,;\s]+', 'split');
            number_pattern = '^[+-]?((\d+\.?\d*)|(\.\d+))([eE][+-]?\d+)?$';
            if numel(tokens) ~= 6 || any(cellfun(@(x) isempty(regexp(x, number_pattern, 'once')), tokens))
                err = 'Enter the box as 6 finite numbers: xlo xhi ylo yhi zlo zhi (in the run''s units).';
                return;
            end
            box = zeros(1, 6);
            for k = 1:6, box(k) = str2double(tokens{k}); end
            if any(~isfinite(box)) || box(1) >= box(2) || box(3) >= box(4) || box(5) >= box(6)
                err = 'Box bounds must be finite and ordered: xlo < xhi, ylo < yhi, zlo < zhi.';
                box = [];
                return;
            end
            ok = true;
        end

        function [ok, hex] = reconstruction_edit_hash_file(obj, path)
            % Read bytes here rather than calling the backend private hash
            % helper. This keeps the deterministic fixture and the live app
            % on the same verified path, including when no backend is bound.
            ok = false; hex = '';
            if isempty(path) || exist(path, 'file') ~= 2, return; end
            fid = fopen(path, 'rb');
            if fid < 0, return; end
            cleanup = onCleanup(@() fclose(fid));
            d = dir(path);
            bytes = fread(fid, d.bytes, '*uint8')';
            if numel(bytes) ~= d.bytes, return; end
            [ok, hex] = obj.reconstruction_edit_hash_bytes(bytes);
            hex = lower(char(hex));
            ok = ok && ~isempty(regexp(hex, '^[0-9a-f]{64}$', 'once'));
        end

        function hex = reconstruction_edit_digest_text(obj, txt)
            [ok, hex] = obj.reconstruction_edit_hash_bytes(uint8(unicode2native(char(txt), 'UTF-8'))); %#ok<ASGLU>
        end

        function [ok, hex] = reconstruction_edit_hash_bytes(obj, bytes) %#ok<INUSD>
            ok = false; hex = '';
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                dg = md.digest(uint8(bytes));
                ub = typecast(int8(dg), 'uint8');
                hex = lower(reshape(dec2hex(ub, 2)', 1, []));
                ok = true;
            catch
            end
        end

        function path = reconstruction_edit_rebase_path(obj, recorded, run_dir)
            % Rebase a recorded run-owned path with the backend's canonical
            % Rules. This is used for copied/moved derived records.
            path = recorded;
            if isempty(recorded) || isempty(run_dir), return; end
            if isstring(recorded), recorded = char(recorded); end
            if isempty(obj.reconstruction_tab)
                tab = rabbit_reconstruction_tab();
            else
                tab = obj.reconstruction_tab;
            end
            runs_dir = fileparts(run_dir);
            recon_dir = fileparts(runs_dir);
            matom_dir = fileparts(recon_dir);
            dataset_root = fileparts(matom_dir);
            try
                path = tab.rebase_run_owned_path(recorded, run_dir, dataset_root);
            catch
                path = recorded;
            end
        end

        function path = reconstruction_edit_manifest_path(obj, run_dir)
            path = '';
            if isempty(run_dir), return; end
            if ~isempty(obj.reconstruction_tab)
                try
                    [path, ~, ~, fail_closed, ~] = obj.reconstruction_tab.active_manifest_path(run_dir);
                    if fail_closed, path = ''; end
                    return;
                catch
                    path = '';
                end
            end
            % Fixture-only fallback: there is no backend pin registry.
            v1 = fullfile(run_dir, 'manifest.json');
            v2 = fullfile(run_dir, 'manifest.v2.json');
            if exist(v1, 'file') == 2
                path = v1;
            elseif exist(v2, 'file') == 2
                path = v2;
            end
        end

        function hex = reconstruction_edit_manifest_hash(obj, run_dir)
            [ok, hex] = obj.reconstruction_edit_hash_file(obj.reconstruction_edit_manifest_path(run_dir));
            if ~ok, hex = ''; end
        end

        function snap = reconstruction_edit_output_snapshot(obj, run_dir)
            snap = struct('path', {}, 'sha256', {}, 'verified', {});
            if isempty(run_dir) || exist(fullfile(run_dir, 'outputs'), 'dir') ~= 7, return; end
            ply_files = dir(fullfile(run_dir, 'outputs', '**', '*.ply'));
            vis_files = dir(fullfile(run_dir, 'outputs', '**', '*.vis'));
            files = [ply_files; vis_files];
            for k = 1:numel(files)
                p = fullfile(files(k).folder, files(k).name);
                [ok, h] = obj.reconstruction_edit_hash_file(p);
                snap(end+1) = struct('path', p, 'sha256', h, 'verified', ok); %#ok<AGROW>
            end
        end

        function p = reconstruction_edit_canonical_path(obj, path) %#ok<INUSD>
            p = '';
            if isempty(path), return; end
            try
                p = char(java.io.File(char(path)).getCanonicalPath());
            catch
                p = char(path);
            end
            p = regexprep(strrep(p, char(92), '/'), '/+$', '');
        end

        function tf = reconstruction_edit_same_path(obj, a, b)
            if isempty(a) || isempty(b), tf = false; return; end
            tf = strcmpi(obj.reconstruction_edit_canonical_path(a), ...
                obj.reconstruction_edit_canonical_path(b));
        end

        function tf = reconstruction_edit_path_in_run(obj, path, run_dir)
            if isempty(path) || isempty(run_dir), tf = false; return; end
            p = lower(obj.reconstruction_edit_canonical_path(path));
            r = lower(obj.reconstruction_edit_canonical_path(run_dir));
            tf = ~isempty(p) && ~isempty(r) && ...
                (strcmp(p, r) || strncmp(p, [r '/'], numel(r) + 1));
        end

        function tf = reconstruction_edit_same_snapshot(obj, a, b)
            tf = false;
            if numel(a) ~= numel(b), return; end
            if ~isempty(a) && (~isfield(a, 'verified') || ~isfield(b, 'verified') || ...
                    any(~[a.verified]) || any(~[b.verified]))
                return;
            end
            for k = 1:numel(a)
                found = false;
                for j = 1:numel(b)
                    if obj.reconstruction_edit_same_path(a(k).path, b(j).path) && ...
                            strcmpi(char(a(k).sha256), char(b(j).sha256))
                        found = true;
                        break;
                    end
                end
                if ~found, return; end
            end
            tf = true;
        end

        function field = reconstruction_edit_manifest_field(obj, operation) %#ok<INUSD>
            switch operation
                case 'touchup', field = 'touchups';
                case 'intensity', field = 'intensity_filters';
                case 'area', field = 'area_removals';
                case 'smooth', field = 'smoothings';
                otherwise, field = '';
            end
        end

        function reconstruction_update_journey(obj)
            % Journey strip, the four step headers and the Step 2 chip.
            % Reads the same gate state enablement uses, so the strip and the
            % control states can never disagree. A header is "n  Name <dash>
            % state", with what to do next when the step is unfinished; the
            % strip repeats the states without the next action. The details
            % (paths, a failed check) are in the tooltips.
            obj.reconstruction_help_update_hint();
            if isempty(obj.reconstruction_tab)
                notes = {'load a recording (File > Load file)', 'load a recording first', ...
                    'load a recording first', 'no run yet: load a recording first'};
                for n = 1:4
                    h = obj.(sprintf('StepHeader%d', n));
                    h.Text = obj.steps_step_text(n, false, notes{n});
                    h.Tooltip = {h.Text};
                end
                obj.JourneyStripLabel.Text = obj.reconstruction_strip_text('', notes);
                obj.JourneyStripLabel.Tooltip = {'Load a recording (File > Load file), or open a saved run (File > Open Reconstruction Manifest).'};
                obj.Step2StatusChip.Text = 'Not supplied';
                return;
            end
            g = obj.reconstruction_gate_state();
            run_id = obj.reconstruction_selected_run_id();
            [note4, tip4] = obj.reconstruction_step4_state(g, run_id);
            notes = {g.step1_note, g.step2_note, g.step3_note, note4};
            tips = {'', '', g.step3_tip, tip4};
            done = [g.step1_ok, g.step2_ok, g.step3_ok, g.step4_ok];
            for n = 1:4
                h = obj.(sprintf('StepHeader%d', n));
                h.Text = obj.steps_step_text(n, done(n), notes{n});
                if isempty(tips{n})
                    h.Tooltip = {h.Text};
                else
                    h.Tooltip = {h.Text; tips{n}};
                end
            end
            obj.ToolsHeader.Text = g.tools_header_text;
            obj.JourneyStripLabel.Text = obj.reconstruction_strip_text(run_id, notes);
            obj.JourneyStripLabel.Tooltip = {'Where each step stands; the step headers below say what to do next.'};
            obj.Step2StatusChip.Text = obj.steps_ternary(g.step2_ok, ...
                'All inputs chosen', ['Inputs: ' g.step2_note]);
        end

        function txt = reconstruction_strip_text(obj, run_id, notes) %#ok<INUSL>
            % "Run <id> | 1 Data: done | 2 Inputs: 3 of 3 | ..." from the
            % header states, each without its next action (the text after a
            % colon or an opening bracket)
            names = {'Data', 'Inputs', 'Tools', 'Run'};
            parts = cell(1, 4);
            for n = 1:4
                st = regexprep(notes{n}, '(:| \().*$', '');
                parts{n} = sprintf('%d %s: %s', n, names{n}, st);
            end
            if isempty(run_id)
                lead = 'New run';
            else
                lead = ['Run ' run_id];
            end
            txt = strjoin([{lead}, parts], ' | ');
        end

        function [note, tip] = reconstruction_step4_state(obj, g, run_id)
            % The Step 4 header's state: the selected run's verdict (the
            % same words as the Results headline), the step it is running,
            % the step it failed at, or what blocks the dataset folder.
            note = g.step4_note;
            tip = '';
            if isempty(run_id) || g.state_unconfirmed || g.cancelling || g.unavailable_run
                return;
            end
            try
                proj = obj.reconstruction_tab.reconstruction_stage_projection(run_id);
            catch
                return;
            end
            names = {proj.stages.name};
            n = numel(obj.reconstruction_tab.stage_order_or_legacy(run_id));
            k_res = find(strcmp(obj.reconstruction_tab.stage_order_or_legacy(run_id), proj.first_resumable_stage), 1);
            switch proj.run_status
                case 'COMPLETED'
                    if g.step4_ok
                        r = obj.reconstruction_tab.run_report(run_id);
                        if ~isempty(r.verdict_words)
                            note = r.verdict_words;
                            tip = r.defect.line;
                            % Under the defect rule the line is the verdict
                            % sentence itself, already in the header text:
                            % said once
                            if strcmp(strtrim(tip), strtrim(note)), tip = ''; end
                        end
                    else
                        note = 'files changed or missing: see Results';
                    end
                case 'RUNNING'
                    if g.stale_running
                        note = 'interrupted: select the run, press Cancel';
                    else
                        k = find([proj.stages.is_current], 1);
                        if isempty(k), k = find(strcmp(names, proj.first_resumable_stage), 1); end
                        if ~isempty(k)
                            k = find(strcmp(obj.reconstruction_tab.stage_order_or_legacy(run_id), names{k}), 1);
                        end
                        if isempty(k)
                            note = 'running';
                        else
                            note = sprintf('running step %d of %d', k, n);
                        end
                    end
                case 'FAILED'
                    if isempty(k_res)
                        note = 'failed: select it, fix, Resume';
                    else
                        note = sprintf('failed at step %d: select it, fix, Resume', k_res);
                    end
                case 'CANCELLED'
                    if isempty(k_res)
                        note = 'cancelled: press Resume';
                    else
                        note = sprintf('cancelled at step %d: press Resume', k_res);
                    end
                case 'INTERRUPTED'
                    % Closed after its session ended: carry it on
                    note = 'interrupted, closed: press Resume';
            end
            % Another run that blocks the folder is said in the tooltip
            if g.stale_running && ~any(strcmp(proj.run_status, {'RUNNING', 'INTERRUPTED'}))
                tip = strtrim([tip ' Another run was interrupted: select it, press Cancel.']);
            end
        end

        function reconstruction_update_enablement(obj)
            % Enable/disable every gated control from the one gate state, and
            % give each disabled control the first missing prerequisite as its
            % tooltip. Presentation only: the callbacks' own uialerts remain
            % the last line of defence.
            g = obj.reconstruction_gate_state();
            % The gate already returns every predicate false when no dataset
            % is bound, so this single pass disables every gated control in
            % the startup/no-dataset state (otherwise the controls would be
            % left at MATLAB's default ENABLED, as nothing else runs on that
            % path).
            obj.ReconstructionRunButton.Enable = obj.steps_pick(g.run_ok);
            obj.ReconstructionRunButton.Tooltip = {g.run_tip};
            obj.ReconstructionResumeButton.Enable = obj.steps_pick(g.resume_ok);
            obj.ReconstructionResumeButton.Tooltip = {g.resume_tip};
            obj.ReconstructionCancelButton.Enable = obj.steps_pick(g.cancel_ok);
            obj.ReconstructionCancelButton.Tooltip = {g.cancel_tip};
            obj.ReconstructionReprojectButton.Enable = obj.steps_pick(g.reproject_ok);
            obj.ReconstructionReprojectButton.Tooltip = {g.reproject_tip};
            obj.ReconstructionVisualiseButton.Enable = obj.steps_pick(g.visualise_ok);
            obj.ReconstructionVisualiseButton.Tooltip = {g.visualise_tip};
            % With a finished run selected, Visualise is the one primary
            % (blue) button: Run starts a new run of several hours
            if g.step4_ok
                obj.ReconstructionRunButton.BackgroundColor = [0.96 0.96 0.96];
                obj.ReconstructionRunButton.FontColor = [0 0 0];
                obj.ReconstructionRunButton.FontWeight = 'normal';
            else
                obj.ReconstructionRunButton.BackgroundColor = obj.primary_colour();
                obj.ReconstructionRunButton.FontColor = [1 1 1];
                obj.ReconstructionRunButton.FontWeight = 'bold';
            end
            obj.ReconstructionCheckToolsButton.Enable = obj.steps_pick(g.checktools_ok);
            obj.ReconstructionCheckToolsButton.Tooltip = {g.checktools_tip};
            obj.ReconstructionCitationsButton.Enable = obj.steps_pick(g.citations_ok);
            obj.ReconstructionCitationsButton.Tooltip = {g.citations_tip};
            obj.ReconstructionRunList.Enable = obj.steps_pick(g.runlist_ok);
            obj.ReconstructionRunList.Tooltip = {g.runlist_tip};
            obj.ReconstructionSparseButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionSparseButton.Tooltip = {g.browse_tip};
            obj.ReconstructionSparseSourceDropDown.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionSfmRecipeDropDown.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionSfmDetailsButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionCalibrationDropDown.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionCalibrateButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionPycamsetGuiButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionCamsetButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionSfmDetailsButton.Tooltip = {g.browse_tip};
            obj.ReconstructionImagesButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionImagesButton.Tooltip = {g.browse_tip};
            obj.ReconstructionRoiButton.Enable = obj.steps_pick(g.browse_ok);
            obj.ReconstructionRoiButton.Tooltip = {g.browse_tip};
            obj.TouchupOpDropDown.Enable = obj.steps_pick(g.touchup_ok);
            obj.TouchupBoxField.Enable = obj.steps_pick(g.touchup_ok);
            obj.TouchupMinFacesField.Enable = obj.steps_pick(g.touchup_ok);
            obj.TouchupPreviewButton.Enable = obj.steps_pick(g.touchup_ok);
            obj.TouchupPreviewButton.Tooltip = {g.touchup_tip};
            obj.TouchupApplyButton.Enable = obj.steps_pick(g.touchup_ok);
            obj.TouchupApplyButton.Tooltip = {g.touchup_tip};
            obj.IntensityModeDropDown.Enable = obj.steps_pick(g.intensity_ok);
            obj.IntensityThresholdField.Enable = obj.steps_pick(g.intensity_ok);
            obj.IntensityPreviewButton.Enable = obj.steps_pick(g.intensity_ok);
            obj.IntensityPreviewButton.Tooltip = {g.intensity_tip};
            obj.IntensityApplyButton.Enable = obj.steps_pick(g.intensity_ok);
            obj.IntensityApplyButton.Tooltip = {g.intensity_tip};
            obj.AreaShapeDropDown.Enable = obj.steps_pick(g.area_ok);
            obj.AreaSelectButton.Enable = obj.steps_pick(g.area_select_ok);
            obj.AreaSelectButton.Tooltip = {g.area_tip};
            obj.AreaPreviewButton.Enable = obj.steps_pick(g.area_ok);
            obj.AreaPreviewButton.Tooltip = {g.area_tip};
            obj.AreaApplyButton.Enable = obj.steps_pick(g.area_ok);
            obj.AreaApplyButton.Tooltip = {g.area_tip};
            obj.SmoothRadiusField.Enable = obj.steps_pick(g.smooth_ok);
            obj.SmoothIterationsField.Enable = obj.steps_pick(g.smooth_ok);
            obj.SmoothStrengthField.Enable = obj.steps_pick(g.smooth_ok);
            obj.SmoothSelectButton.Enable = obj.steps_pick(g.smooth_select_ok);
            obj.SmoothSelectButton.Tooltip = {g.smooth_tip};
            obj.SmoothPreviewButton.Enable = obj.steps_pick(g.smooth_ok);
            obj.SmoothPreviewButton.Tooltip = {g.smooth_tip};
            obj.SmoothApplyButton.Enable = obj.steps_pick(g.smooth_ok);
            obj.SmoothApplyButton.Tooltip = {g.smooth_tip};
            % Empty state: the runs-list hint replaces an empty listbox.
            obj.ReconstructionRunListEmptyLabel.Visible = obj.steps_pick(g.no_runs);
            % An empty list is hidden (its empty box still draws scroll bars)
            obj.ReconstructionRunList.Visible = obj.steps_pick(~g.no_runs);
            obj.ReconstructionRunListEmptyLabel.Text = g.runlist_empty_text;
            obj.reconstruction_update_run_folder_button();
            % A control that IS enabled must not carry a "missing
            % prerequisite" tooltip: clear the tip
            % wherever the gate just enabled the control.
            obj.steps_clear_enabled_tips();
            obj.reconstruction_path_tooltips();
            obj.reconstruction_selection_status(false, g);
        end

        function reconstruction_path_tooltips(obj)
            %% Step 2's path fields: the full path as the tooltip's last line
            % A long path is cut at the field's right
            % edge, so its end (the folder or file name) is not seen. The
            % edit fields of R2026a have no focus callbacks, so the field
            % cannot show the path cut from the left while unfocused and in
            % full on focus; the tooltip gives it in full instead, below the
            % field's own tip. The Value is untouched.
            for f = {obj.ReconstructionImagesField, obj.ReconstructionRoiField, obj.ReconstructionSparseField}
                h = f{1};
                if isempty(h) || ~isvalid(h), continue; end
                tip = cellstr(h.Tooltip);
                tip = tip(~startsWith(tip, 'Full path: ') & ~cellfun(@isempty, tip));
                v = strtrim(char(h.Value));
                if ~isempty(v)
                    tip{end + 1} = ['Full path: ' rabbit_reconstruction_tab.display_path(v)]; %#ok<AGROW>
                end
                if isempty(tip), tip = ''; end
                h.Tooltip = tip;
            end
        end

        function reconstruction_selection_status(obj, force, g)
            % The status box under Visualise says which run is selected.
            % force: write it even over a viewer message (the user picked
            % a run); otherwise only the two plain prompts are replaced,
            % so a message from the viewer stays until the selection changes.
            prompt = 'Select a run, then Visualise.';
            cur = strjoin(cellstr(obj.VisualiseStatusText.Value), ' ');
            if ~force && ~strcmp(cur, prompt) && ~startsWith(cur, 'Selected run ')
                return;
            end
            try
                run_id = obj.reconstruction_selected_run_id();
            catch
                run_id = '';
            end
            if isempty(run_id)
                txt = prompt;
            else
                if nargin < 3, g = obj.reconstruction_gate_state(); end
                if g.visualise_ok
                    txt = sprintf('Selected run %s: press Visualise to see its models.', run_id);
                else
                    txt = sprintf('Selected run %s. %s', run_id, g.visualise_tip);
                end
            end
            if ~strcmp(cur, txt)
                obj.VisualiseStatusText.Value = {txt};
            end
        end

        function steps_clear_enabled_tips(obj)
            % Give every control this pass ENABLED its plain description
            % back, so an enabled control never claims a missing
            % prerequisite. Reads the same gate the enablement pass used.
            g = obj.reconstruction_gate_state();
            pairs = {
                'ReconstructionRunButton', g.run_ok
                'ReconstructionResumeButton', g.resume_ok
                'ReconstructionCancelButton', g.cancel_ok
                'ReconstructionReprojectButton', g.reproject_ok
                'ReconstructionVisualiseButton', g.visualise_ok
                'ReconstructionCheckToolsButton', g.checktools_ok
                'ReconstructionCitationsButton', g.citations_ok
                'TouchupPreviewButton', g.touchup_ok
                'TouchupApplyButton', g.touchup_ok
                'IntensityPreviewButton', g.intensity_ok
                'IntensityApplyButton', g.intensity_ok
                'AreaSelectButton', g.area_select_ok
                'AreaPreviewButton', g.area_ok
                'AreaApplyButton', g.area_ok
                'SmoothSelectButton', g.smooth_select_ok
                'SmoothPreviewButton', g.smooth_ok
                'SmoothApplyButton', g.smooth_ok
                'ReconstructionSparseButton', g.browse_ok
                'ReconstructionSfmDetailsButton', g.browse_ok
                'ReconstructionImagesButton', g.browse_ok
                'ReconstructionRoiButton', g.browse_ok
                'ReconstructionRunList', g.runlist_ok
            };
            for k = 1:size(pairs, 1)
                if pairs{k, 2}
                    obj.(pairs{k, 1}).Tooltip = {obj.reconstruction_static_tip(pairs{k, 1})};
                end
            end
        end

        function ok = reconstruction_assert_no_active_run(obj)
            % The eight session-destroying entries call this first.
            %
            % LIVE active run  -> BLOCK: ok=false, the blocking alert, and the
            %                     caller returns early.
            % STALE (dead-lock) -> WARN-ONLY: ok=TRUE so the
            %                     entry proceeds; the alert names the real
            %                     action (Cancel closes it). Blocking here
            %                     would strand a user whose run died
            %                     overnight.
            % One classification only: this reads the same gate state the
            % strip and the enablement pass read, so the three can never
            % disagree.
            ok = true;
            if isempty(obj.reconstruction_tab)
                return;
            end
            g = obj.reconstruction_gate_state();
            if g.active_run
                ok = false;
                uialert(obj.host.opticalmappingUIFigure, ...
                    ['A reconstruction run is active. Cancel it before restarting the APP - ' ...
                     'restarting closes this session.'], ...
                    'Reconstruction run active');
                return;
            end
            if g.unavailable_run
                % Fail closed: the run may be alive and we could not tell.
                ok = false;
                uialert(obj.host.opticalmappingUIFigure, ...
                    ['A reconstruction run on this dataset may still be running (its lock ' ...
                     'could not be inspected). Cancel it from that session, or restart the ' ...
                     'workstation to clear the lock.'], ...
                    'Reconstruction run active');
                return;
            end
            if g.stale_running
                % warn-only: the user may proceed.
                uialert(obj.host.opticalmappingUIFigure, ...
                    ['A reconstruction run on this dataset is marked RUNNING, but nothing is ' ...
                     'running it (INTERRUPTED). Select it in Step 4 and choose Cancel to close it.'], ...
                    'Reconstruction run interrupted');
            end
        end

        function reconstruction_check_tools(obj)
            if isempty(obj.reconstruction_tab)
                obj.StepHeader3.Text = obj.steps_step_text(3, false, 'load a recording first');
                return;
            end
            [sync_ok, sync_err] = obj.reconstruction_sync_tool_paths();
            if ~sync_ok
                obj.StepHeader3.Text = obj.steps_step_text(3, false, 'check failed: see message');
                obj.StepHeader3.Tooltip = {['Check tools failed: ' sync_err]};
                return;
            end
            source = obj.reconstruction_sparse_source();
            stages = rabbit_reconstruction_tab.stage_order_for_source(source, ...
                obj.ReconstructionCloudSourceDropDown.Value, obj.ReconstructionDenseDropDown.Value);
            recipe = [];
            if strcmp(source, 'built')
                recipe = obj.reconstruction_sfm_recipe();
            end
            first_fail = '';
            for k = 1:numel(stages)
                if strcmp(stages{k}, 'sparse_build')
                    if isempty(recipe)
                        ok = false;
                        results = struct('name', 'sfm_recipe', 'ok', false, ...
                            'message', 'The sparse model recipe file could not be read.');
                    else
                        [ok, results] = obj.reconstruction_tab.preflight(stages{k}, struct('sfm_recipe', recipe));
                    end
                else
                    [ok, results] = obj.reconstruction_tab.preflight(stages{k});
                end
                [stage_ok, stage_message] = obj.reconstruction_preflight_result( ...
                    obj.reconstruction_stage_label(stages{k}, stages), ok, results);
                if ~stage_ok
                    first_fail = stage_message;
                    break;
                end
            end
            obj.reconstruction_tools_checked_paths = obj.reconstruction_tool_paths_key();
            if isempty(first_fail)
                obj.reconstruction_tools_check_result = 'OK';
            else
                obj.reconstruction_tools_check_result = first_fail;
            end
            % The header (and the failure in its tooltip) from the gate
            obj.reconstruction_update_journey();
        end

        function key = reconstruction_tool_paths_key(obj)
            % The tool paths as one string, to tell whether a check is current
            key = strjoin({obj.ReconstructionColmapField.Value, obj.ReconstructionApdField.Value, ...
                obj.ReconstructionRunPyField.Value, obj.ReconstructionPythonField.Value, ...
                obj.ReconstructionModelsField.Value}, '|');
        end
        function [state, pid, message] = reconstruction_lock_liveness(obj, run_id)
            % Live/dead classification of a run's lock. The grammar that
            % EXISTS (create_run, rabbit_reconstruction_tab.m ~L349):
            %   .lock holds pid=<n>, timestamp=<iso>, run_id=<id>.
            %   state: one of 'NONE', 'STALE', 'LIVE', 'UNAVAILABLE'
            % A missing/unreadable lock is STALE (dead), never "live"; an
            % unreadable pid is STALE; an uninspectable process is
            % UNAVAILABLE (never silently treated as dead).
            state = 'NONE';
            pid = NaN;
            message = 'No run selected.';
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            % The run folder is derived from the public dataset field: the
            % backend's run_dir_for is private, so reaching for it from the
            % app throws MATLAB:CannotAccessMethod whenever a RUNNING run
            % exists. Layout, per the backend:
            %   <dataset_root>/<stem>.matom/reconstruction/runs/<run_id>
            ds = obj.ReconstructionDatasetField.Value;
            if isempty(ds)
                message = 'No dataset bound.';
                return;
            end
            [ds_root, ds_stem] = fileparts(ds);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', 'runs', run_id);
            if ~exist(run_dir, 'dir')
                % The run folder is gone: no process can be holding this run
                % open, so the state is provably dead - not uninspectable.
                % (The initial NONE state would be treated as unavailable
                % and block load / restart / close.)
                state = 'STALE';
                message = 'The run folder no longer exists.';
                return;
            end
            lock = fullfile(run_dir, '.lock');
            if ~exist(lock, 'file')
                state = 'STALE';
                message = 'No lock file - the run is not active.';
                return;
            end
            try
                raw = fileread(lock);
            catch
                state = 'UNAVAILABLE';
                message = 'The run''s lock file could not be read.';
                return;
            end
            tok = regexp(raw, 'pid=(\d+)', 'tokens', 'once');
            if isempty(tok)
                % A malformed/truncated lock does not prove the owner is dead.
                % Classify UNAVAILABLE so the guard fails closed (STALE here
                % would let a possibly-live run be destroyed).
                state = 'UNAVAILABLE';
                message = 'The lock holds no readable process id.';
                return;
            end
            pid = str2double(tok{1});
            if isnan(pid)
                state = 'UNAVAILABLE';
                message = 'The lock''s process id is unreadable.';
                return;
            end
            % One classification: the backend's, which also reads the computer
            % named in the lock and works on every platform.
            state = obj.reconstruction_tab.run_inspect_lock_liveness(run_dir);
            switch state
                case 'STALE'
                    message = 'The MATLAB session that ran it has ended.';
                case 'LIVE'
                    message = 'The run''s process is alive.';
                otherwise
                    message = 'The run''s process could not be inspected from this computer.';
            end
        end

        function reconstruction_on_step_header_toggled(obj, src, ~)
            % Accordion toggle: one step expanded at a time. The callback sets
            % Both Visible and the parent RowHeight (a hidden child grid does
            % Not shrink its parent row). The pressed header identifies itself
            % through the source handle the anonymous wrapper forwards.
            names = {'StepHeader1', 'StepHeader2', 'StepHeader3', 'StepHeader4'};
            idx = 0;
            for k = 1:numel(names)
                if isequal(src, obj.(names{k}))
                    idx = k;
                end
            end
            if idx == 0
                return;
            end
            open_now = obj.reconstruction_step_open();
            if open_now == idx
                obj.reconstruction_set_accordion(0, obj.reconstruction_tools_open());
            else
                obj.reconstruction_set_accordion(idx, obj.reconstruction_tools_open());
            end
        end

        function reconstruction_on_tools_header_toggled(obj, ~, ~)
            % The ToolsPanel toggles independently of the four steps.
            open_now = obj.reconstruction_tools_open();
            obj.reconstruction_set_accordion(obj.reconstruction_step_open(), ~open_now);
        end

        function reconstruction_init_accordion(obj)
            % Initial state: all steps collapsed and the tools collapsed, so
            % the whole journey is visible at a glance and Step 1 is the
            % obvious start.
            obj.reconstruction_set_accordion(0, false);
        end

        function ReconstructionRunListValueChanged(obj, ~, ~)
            obj.AreaSelection = [];
            obj.SmoothSelection = [];
            try, if ~isempty(obj.AreaFigure) && isgraphics(obj.AreaFigure), close(obj.AreaFigure); end, catch, end
            try, if ~isempty(obj.SmoothFigure) && isgraphics(obj.SmoothFigure), close(obj.SmoothFigure); end, catch, end
            obj.AreaFigure = [];
            obj.SmoothFigure = [];
            run_id = obj.reconstruction_selected_run_id();
            if ~isempty(run_id)
                obj.reconstruction_render_status(run_id);
            end
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            obj.reconstruction_selection_status(true);
            obj.reconstruction_edit_refresh();
            obj.reconstruction_open_finished_run();
            % The CV tab's scale line compares
            % the cube's pixel size with the selected run's heart surface
            try
                rabbit_calibration_scale.show(obj.host);
            catch
                % a test double without the Conduction Velocity tab
            end
        end

        function reconstruction_open_finished_run(obj)
            % A finished run selected: Step 4 (Visualise, Redo projection)
            % is the section shown
            run_id = obj.reconstruction_selected_run_id();
            if isempty(run_id) || ~obj.reconstruction_run_complete(run_id), return; end
            if obj.reconstruction_step_open() ~= 4
                obj.reconstruction_set_accordion(4, false);
            end
        end

        function ReconstructionStageListValueChanged(obj, ~, ~)
            % A step was selected: its warnings, attempts and log
            if isempty(obj.reconstruction_tab), return; end
            run_id = obj.reconstruction_selected_run_id();
            if isempty(run_id), return; end
            sel_st = obj.reconstruction_selected_stage();
            if isempty(sel_st), return; end
            obj.reconstruction_show_step(run_id, sel_st);
        end

        function [ok, message] = reconstruction_sync_tool_paths(obj)
            % Push the field values into the backend state before any
            % preflight, so the Step-3 chips and the Run preflight can never
            % try different paths. `set_tool_path` persists the state.
            % Validate the state container before the first write: a malformed
            % tab-state such as `"tool_paths": 42` must fail closed rather
            % than reach set_tool_path's dynamic field assignment.
            ok = true;
            message = '';
            obj.reconstruction_note_typed_tool_paths();
            if isempty(obj.reconstruction_tab)
                return;
            end
            [ok, message] = obj.reconstruction_tool_state_valid();
            if ~ok
                return;
            end
            fields = obj.reconstruction_tool_fields();
            for k = 1:size(fields, 1)
                v = obj.(fields{k, 2}).Value;
                if isstring(v) && isscalar(v)
                    v = char(v);
                end
                if ischar(v) && ~isempty(v)
                    obj.reconstruction_tab.set_tool_path(fields{k, 1}, v);
                end
            end
        end

        function [ok, out] = steps_scalar_text(obj, value) %#ok<INUSD>
            % Convert exactly one non-empty text value; reject numeric,
            % object, cell and missing values before any strcmp/formatting.
            ok = false;
            out = '';
            if ischar(value)
                if isrow(value) && ~isempty(strtrim(value))
                    out = value;
                    ok = true;
                end
            elseif isstring(value)
                if isscalar(value) && ~ismissing(value)
                    out = char(value);
                    ok = isrow(out) && ~isempty(strtrim(out));
                end
            end
        end

        function [ok, out] = steps_run_status_text(obj, value)
            % Tab-state status is a closed enum. Keeping this validation
            % beside the text-type guard prevents a malformed status from
            % reaching strcmp, sprintf or the journey gate.
            [ok, out] = obj.steps_scalar_text(value);
            if ok
                ok = any(strcmp(out, {'CREATED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED', 'INTERRUPTED'}));
            end
            if ~ok
                out = '';
            end
        end

        function tf = steps_run_id_valid(obj, value)
            % Run IDs are immutable backend identifiers, not path fragments:
            % one folder name, letters, digits, _ and - only, checked before
            % any list display, manifest read, lock check or destructive
            % action. Generated IDs are yyyyMMddTHHmmss_8hex.
            [ok, out] = obj.steps_scalar_text(value);
            tf = ok && ~isempty(regexp(out, '^[A-Za-z0-9][A-Za-z0-9_-]*$', 'once'));
        end

        function [ok, message] = reconstruction_tool_state_valid(obj)
            % Validate the durable state container before dynamic writes or
            % preflight. Struct arrays are not scalar tool-path records.
            ok = false;
            message = 'The reconstruction state is unavailable.';
            if isempty(obj.reconstruction_tab)
                message = 'Load a dataset first (File > Load file).';
                return;
            end
            try
                state = obj.reconstruction_tab.get_state();
            catch err
                message = ['The reconstruction state could not be read: ' err.message];
                return;
            end
            if ~isstruct(state) || ~isscalar(state)
                message = 'The stored reconstruction state is malformed; reload the dataset state.';
                return;
            end
            if isfield(state, 'tool_paths') && ...
                    (~isstruct(state.tool_paths) || ~isscalar(state.tool_paths))
                message = 'The stored tool paths are malformed; reload or repair the dataset state before running.';
                return;
            end
            ok = true;
            message = '';
        end

        function [ok, message] = reconstruction_action_gate(obj, action)
            % Recompute the action-specific predicate at click time. The
            % enablement repaint is presentation only; files, locks, maps,
            % manifests, and selections can change before a callback runs.
            % Run reads the same gate on both sparse model routes.
            ok = false;
            message = 'The reconstruction action is no longer available; the view has been refreshed.';
            try
                [state_ok, state_message] = obj.reconstruction_tool_state_valid();
                if ~state_ok && ~strcmp(action, 'visualise')
                    message = state_message;
                    return;
                end
                g = obj.reconstruction_gate_state();
                switch lower(action)
                    case {'run', 'resume', 'reproject', 'visualise', 'touchup', 'intensity', ...
                            'area', 'area_select', 'smooth', 'smooth_select'}
                        ok = g.([lower(action) '_ok']);
                    otherwise
                        message = 'Unknown reconstruction action.';
                        return;
                end
                if ~ok
                    % The two select actions share the tip of their tool
                    tip = g.([strrep(lower(action), '_select', '') '_tip']);
                    if ~isempty(tip)
                        message = tip;
                    end
                end
            catch err
                ok = false;
                message = ['The reconstruction prerequisite check failed: ' err.message];
            end
        end

        function [ok, message] = reconstruction_preflight_result(obj, stage, nominal_ok, results)
            % Normalise backend preflight output before any field indexing.
            % Malformed or contradictory results fail closed with a stage
            % name. A failing check must say why; a passing one need not.
            ok = false;
            message = sprintf('%s - malformed preflight result.', stage);
            if ~(islogical(nominal_ok) && isscalar(nominal_ok))
                return;
            end
            if ~isstruct(results) || isempty(results)
                return;
            end
            for k = 1:numel(results)
                if ~isfield(results(k), 'ok') || ...
                        ~isfield(results(k), 'name') || ~isfield(results(k), 'message') || ...
                        ~(islogical(results(k).ok) && isscalar(results(k).ok))
                    return;
                end
                [name_ok, ~] = obj.steps_scalar_text(results(k).name);
                if ~name_ok
                    return;
                end
                if ~results(k).ok
                    [msg_ok, msg] = obj.steps_scalar_text(results(k).message);
                    if ~msg_ok
                        return;
                    end
                    results(k).message = msg;
                end
            end
            if nominal_ok
                if ~all([results.ok])
                    message = sprintf('%s - preflight reported success with a failing stage.', stage);
                    return;
                end
                ok = true;
                message = '';
                return;
            end
            bad = find(~[results.ok], 1, 'first');
            if isempty(bad)
                message = sprintf('%s - preflight returned failure without a failing stage.', stage);
            else
                message = sprintf('%s - %s', stage, results(bad).message);
            end
        end

        function tf = reconstruction_selection_source_matches(obj, kind, selection, run_id)
            % Require the interactive operation to target the same source
            % bytes that were selected, not merely the same run ID. Uses
            % the descriptor Preview and Apply are bound to.
            tf = false;
            if ~isstruct(selection) || ~isscalar(selection) || ...
                    ~isfield(selection, 'source_ply') || ~isfield(selection, 'source_sha256')
                return;
            end
            [path_ok, selected_path] = obj.steps_scalar_text(selection.source_ply);
            [hash_ok, selected_hash] = obj.steps_scalar_text(selection.source_sha256);
            if ~(path_ok && hash_ok)
                return;
            end
            try
                [ok, ~, d] = obj.reconstruction_edit_descriptor(kind, run_id, selection);
                if ~ok || ~obj.reconstruction_edit_same_path(d.path, selected_path)
                    return;
                end
                tf = strcmpi(char(d.sha256), selected_hash);
            catch
                tf = false;
            end
        end

        function reconstruction_safe_refresh(obj)
            % Never let a failed action's repaint path throw or strand enabled
            % controls. Each presentation pass is independently contained.
            try
                obj.reconstruction_update_journey();
            catch
                try, obj.JourneyStripLabel.Text = 'Reconstruction state unavailable - refresh or reload the dataset.'; catch, end
            end
            try
                obj.reconstruction_update_enablement();
            catch
                names = {'ReconstructionRunButton','ReconstructionResumeButton', ...
                    'ReconstructionCancelButton','ReconstructionReprojectButton', ...
                    'ReconstructionVisualiseButton','TouchupPreviewButton', ...
                    'TouchupApplyButton','IntensityPreviewButton','IntensityApplyButton', ...
                    'AreaSelectButton','AreaPreviewButton','AreaApplyButton', ...
                    'SmoothSelectButton','SmoothPreviewButton','SmoothApplyButton'};
                for k = 1:numel(names)
                    try, obj.(names{k}).Enable = 'off'; catch, end
                end
            end
        end

        function runs = reconstruction_validated_runs(obj)
            % Return only scalar run records with text id + closed-enum
            % status. Handles both struct arrays and heterogeneous CELL
            % arrays produced by jsondecode. Malformed entries are absent,
            % never selectable and never allowed to hide a valid RUNNING run.
            runs = struct('id', {}, 'status', {});
            if isempty(obj.reconstruction_tab)
                return;
            end
            try
                state = obj.reconstruction_tab.get_state();
            catch
                return;
            end
            if ~isstruct(state) || ~isscalar(state) || ...
                    ~isfield(state, 'runs') || isempty(state.runs)
                return;
            end
            raw = state.runs;
            if isstruct(raw)
                entries = num2cell(raw);
            elseif iscell(raw)
                entries = raw;
            else
                return;
            end
            for k = 1:numel(entries)
                entry = entries{k};
                if ~isstruct(entry) || numel(entry) ~= 1 || ...
                        ~isfield(entry, 'id') || ~isfield(entry, 'status')
                    continue;
                end
                [id_ok, run_id] = obj.steps_scalar_text(entry.id);
                [status_ok, run_status] = obj.steps_run_status_text(entry.status);
                id_ok = id_ok && obj.steps_run_id_valid(run_id);
                if ~(id_ok && status_ok)
                    continue;
                end
                runs(end+1) = struct('id', run_id, 'status', run_status); %#ok<AGROW>
            end
        end

        function fields = reconstruction_tool_fields(~)
            % Step 3 tool paths: backend key, edit field, field label
            fields = {'colmap_exe', 'ReconstructionColmapField', 'COLMAP exe'; ...
                      'apd_exe', 'ReconstructionApdField', 'APD.exe'; ...
                      'apde_run_py', 'ReconstructionRunPyField', 'APDe-MVS run.py'; ...
                      'apde_python_env', 'ReconstructionPythonField', 'Python env'; ...
                      'colmap_models_dir', 'ReconstructionModelsField', 'COLMAP models'};
        end

        function reconstruction_show_tool_paths(obj, s)
            %% Fill the step 3 tool fields for an opened dataset or run
            % s: the tab state. Each field gets
            % rabbit_reconstruction_tab.resolve_tool_path: a path typed in
            % this session, else the dataset's saved path if it exists,
            % else the last used path if it exists, else the OM_*
            % environment variable, else empty. A saved path that no
            % longer exists is passed over with a note in the step 3
            % header; if nothing else exists it is shown, and Check tools
            % says it was not found.
            fields = obj.reconstruction_tool_fields();
            mem = obj.reconstruction_tool_memory;
            notes = {};
            for k = 1:size(fields, 1)
                tool = fields{k, 1};
                saved = '';
                if isfield(s, 'tool_paths') && isstruct(s.tool_paths) && isscalar(s.tool_paths) && isfield(s.tool_paths, tool) && ...
                        (ischar(s.tool_paths.(tool)) || (isstring(s.tool_paths.(tool)) && isscalar(s.tool_paths.(tool))))
                    saved = char(s.tool_paths.(tool));
                end
                typed = '';
                if isfield(mem.typed, tool)
                    typed = mem.typed.(tool);
                end
                [p, ~, note] = rabbit_reconstruction_tab.resolve_tool_path(tool, typed, saved);
                obj.(fields{k, 2}).Value = p;
                mem.shown.(tool) = p;
                if ~isempty(note)
                    notes{end+1} = sprintf('%s: %s', fields{k, 3}, note); %#ok<AGROW>
                end
            end
            mem.note = strjoin(notes, '; ');
            obj.reconstruction_tool_memory = mem;
        end

        function reconstruction_note_typed_tool_paths(obj)
            %% Keep the tool paths the user changed
            % A field whose value differs from what the app last put there
            % was typed or browsed to: it wins for the rest of this app
            % session (also for other datasets) and is stored as the last
            % used path (an existing path only; empty forgets it).
            fields = obj.reconstruction_tool_fields();
            mem = obj.reconstruction_tool_memory;
            for k = 1:size(fields, 1)
                tool = fields{k, 1};
                v = strtrim(char(obj.(fields{k, 2}).Value));
                shown = '';
                if isfield(mem.shown, tool)
                    shown = mem.shown.(tool);
                end
                if ~strcmp(v, shown)
                    mem.typed.(tool) = v;
                    mem.shown.(tool) = v;
                    rabbit_reconstruction_tab.remember_tool_path(tool, v);
                end
            end
            obj.reconstruction_tool_memory = mem;
        end

        function reconstruction_browse_tool(obj, tool)
            %% Browse... next to a step 3 tool field
            % Opens a file (or, for the COLMAP models, a folder) selector
            % in the folder of the current path; the choice is handled as
            % a typed path. Cancel changes nothing.
            fields = obj.reconstruction_tool_fields();
            k = find(strcmp(fields(:, 1), tool), 1);
            f = obj.(fields{k, 2});
            cur = strtrim(char(f.Value));
            start = '';
            if isfolder(cur)
                start = cur;
            elseif ~isempty(cur) && isfolder(fileparts(cur))
                start = fileparts(cur);
            end
            if strcmp(tool, 'colmap_models_dir')
                d = uigetdir(start, 'Choose the COLMAP models folder');
                if isequal(d, 0), return; end
                choice = d;
            else
                if ispc
                    exe = {'*.exe;*.bat', 'Programs (*.exe, *.bat)'};
                else
                    exe = {'*', 'All files'};
                end
                switch tool
                    case 'colmap_exe'
                        filt = exe; ttl = 'Choose the COLMAP program';
                    case 'apd_exe'
                        filt = exe; ttl = 'Choose APD.exe (APDe-MVS)';
                    case 'apde_run_py'
                        filt = {'*.py', 'Python scripts (*.py)'}; ttl = 'Choose the APDe-MVS run.py';
                    otherwise
                        filt = exe; ttl = 'Choose the Python interpreter of the APDe-MVS environment';
                end
                if isempty(start)
                    [fn, pth] = uigetfile(filt, ttl);
                else
                    [fn, pth] = uigetfile(filt, ttl, [start filesep]);
                end
                if isequal(fn, 0), return; end
                choice = fullfile(pth, fn);
            end
            f.Value = choice;
            obj.ReconstructionToolPathChanged();
        end

        % ---- gate state + accordion helpers (private) ---------------------

        function g = reconstruction_gate_state(obj)
            % The SINGLE gate computation. The strip, the enablement pass and
            % the mid-run guard all read this, so their states cannot
            % disagree. Every field is a plain scalar or char row vector.
            g = obj.steps_blank_gate();
            if isempty(obj.reconstruction_tab)
                % Every gated control is disabled in this state, so each must
                % carry the first-missing prerequisite.
                tip = 'Load a dataset first (File > Load file).';
                g.run_tip = tip;
                g.resume_tip = tip;
                g.cancel_tip = tip;
                g.reproject_tip = tip;
                g.visualise_tip = tip;
                g.checktools_tip = tip;
                g.citations_tip = tip;
                g.runlist_tip = tip;
                g.touchup_tip = tip;
                g.intensity_tip = tip;
                g.area_tip = tip;
                g.smooth_tip = tip;
                return;
            end
            g.dataset_bound = ~isempty(obj.ReconstructionDatasetField.Value);
            g.map_ok = ~isempty(obj.host.processed_data.activation_map) && ...
                obj.reconstruction_map_matches_dataset();
            g.restore_mode = obj.reconstruction_restore_mode;
            [g.tool_state_ok, g.tool_state_tip] = obj.reconstruction_tool_state_valid();

            % ---- runs: ACTIVE means RUNNING with a LIVE lock ---------------
            % Normalise every tab-state entry before any consumer reads it.
            % jsondecode can produce a heterogeneous CELL array when one run
            % object is missing a field; iterating the raw value either throws
            % or silently drops a live run. The validator preserves every
            % well-formed entry and excludes malformed entries as absent.
            runs = obj.reconstruction_validated_runs();
            % The durable manifest is the authority for destructive actions:
            % cancel_run() writes it unconditionally, so gating on tab-state
            % alone lets a click convert a COMPLETED manifest to CANCELLED.
            % Reconcile each run's tab-state
            % status with its manifest before classifying.
            unreadable_seen = false;
            for k = 1:numel(runs)
                % A manifest that EXISTS but is
                % unreadable must not leave the tab-state status in place for
                % active-run classification, and must never be treated as a
                % benign non-RUNNING status. The tab-state could say COMPLETED
                % (safe) or RUNNING (dangerous); classifying from stale state
                % lets a possibly-live run be destroyed. Fail closed instead:
                % mark the status so every comparison misses, and raise the
                % UNAVAILABLE flag the destructive paths already honour.
                % A runs entry missing `status` throws on any dereference
                % below, so it is guarded here.
                if ~isfield(runs(k), 'id') || ~isfield(runs(k), 'status')
                    continue;
                end
                if obj.reconstruction_manifest_exists(runs(k).id)
                    dstatus = obj.reconstruction_manifest_status(runs(k).id);
                    if isempty(dstatus)
                        runs(k).status = '<unreadable>';
                        unreadable_seen = true;
                    elseif ~strcmp(dstatus, runs(k).status)
                        runs(k).status = dstatus;
                    end
                end
            end
            if unreadable_seen
                g.unavailable_run = true;
            end
            g.no_runs = isempty(runs);
            run_id = obj.reconstruction_selected_run_id();
            g.run_selected = ~isempty(run_id);
            g.cancelling = g.run_selected && obj.reconstruction_cancel_pending(run_id);
            g.state_unconfirmed = ~isempty(obj.unconfirmed_run_id) && ...
                (~g.run_selected || strcmp(obj.unconfirmed_run_id, run_id));
            [g.provenance_ok, g.provenance_tip] = obj.reconstruction_provenance_state(run_id);
            for k = 1:numel(runs)
                if ~strcmp(runs(k).status, 'RUNNING')
                    continue;
                end
                st = obj.reconstruction_lock_liveness(runs(k).id);
                if strcmp(st, 'LIVE')
                    g.active_run = true;
                elseif strcmp(st, 'STALE')
                    g.stale_running = true;
                else
                    % UNINSPECTABLE (a foreign/elevated owner, or a check that
                    % could not answer): FAIL CLOSED. Folding this into the
                    % warn-only stale path would let a possibly-live run be
                    % destroyed.
                    g.unavailable_run = true;
                end
            end
            % ACTIVE = live, stale, liveness unknown, cancellation pending, or
            % a failed persistence/read-back confirmation (all block writes).
            g.active_run_or_stale = g.active_run || g.stale_running || g.unavailable_run || ...
                g.cancelling || g.state_unconfirmed;

            % ---- step completeness -----------------------------------------
            sparse_set = ~isempty(strtrim(obj.ReconstructionSparseField.Value));
            images_set = ~isempty(strtrim(obj.ReconstructionImagesField.Value));
            roi_set = ~isempty(strtrim(obj.ReconstructionRoiField.Value));
            % The APDe-MVS paths are needed only when the run has the
            % APDe-MVS steps ("APDe-MVS + COLMAP")
            needs_apde = strcmp(obj.ReconstructionDenseDropDown.Value, 'both');
            tools_set = ~isempty(strtrim(obj.ReconstructionColmapField.Value)) && ...
                        (~needs_apde || ( ...
                        ~isempty(strtrim(obj.ReconstructionApdField.Value)) && ...
                        ~isempty(strtrim(obj.ReconstructionRunPyField.Value)) && ...
                        ~isempty(strtrim(obj.ReconstructionPythonField.Value)))) && ...
                        g.tool_state_ok;
            g.step1_ok = g.dataset_bound;
            g.step1_note = obj.steps_ternary(g.step1_ok, 'done', 'load a recording (File > Load file)');
            if strcmp(obj.reconstruction_sparse_source(), 'built')
                % Build mode: the recipe takes the place of the sparse model
                recipe_ok = ~strcmp(obj.ReconstructionSfmRecipeDropDown.Value, 'custom') || ...
                    ~isempty(obj.reconstruction_sfm_recipe_file);
                g.step2_ok = images_set && roi_set && recipe_ok;
                have = [images_set roi_set recipe_ok];
                need = {'choose the reconstruction images', 'choose the regions file', 'choose the recipe file'};
            else
                g.step2_ok = sparse_set && images_set && roi_set;
                have = [sparse_set images_set roi_set];
                need = {'choose the sparse model', 'choose the reconstruction images', 'choose the regions file'};
            end
            % "3 of 3", or the count and the first thing still to choose
            if all(have)
                g.step2_note = sprintf('%d of %d', sum(have), numel(have));
            else
                g.step2_note = sprintf('%d of %d: %s', sum(have), numel(have), need{find(~have, 1)});
            end
            g.step3_ok = tools_set;
            % Step 3 says "ready" only after Check tools passed for these paths
            unchecked = ~strcmp(obj.reconstruction_tools_checked_paths, obj.reconstruction_tool_paths_key()) || ...
                    isempty(obj.reconstruction_tools_check_result);
            % The header says the state and what to do; the details (a
            % failed check, a saved path that is gone) are in its tooltip
            g.step3_tip = '';
            if ~g.tool_state_ok
                g.step3_note = 'not ready: see the tooltip';
                g.step3_tip = g.tool_state_tip;
            elseif ~tools_set && needs_apde
                g.step3_note = 'not set: set all four tool paths';
            elseif ~tools_set
                g.step3_note = 'not set: set the COLMAP path';
            elseif unchecked
                g.step3_note = 'not checked: press Check tools';
            elseif strcmp(obj.reconstruction_tools_check_result, 'OK')
                g.step3_note = 'checked';
            else
                g.step3_note = 'check failed: see message';
                g.step3_tip = ['Check tools failed: ' obj.reconstruction_tools_check_result];
            end
            % A finished run selected: it is viewed and projected again
            % without the tools, so the header does not ask for them
            if ~isempty(run_id) && any(startsWith(g.step3_note, {'not set', 'not checked'})) && ...
                    obj.reconstruction_run_complete(run_id)
                g.step3_note = [extractBefore([g.step3_note ':'], ':') ' (needed only to run or resume)'];
            end
            % A dataset path that no longer exists was replaced when the
            % dataset was opened: say so until the tools are checked
            if unchecked && ~isempty(obj.reconstruction_tool_memory.note)
                g.step3_tip = strtrim([obj.reconstruction_tool_memory.note ' ' g.step3_tip]);
            end
            % Step 4 "complete" means the run produced its canonical output -
            % Not merely that a row is selected (otherwise a FAILED run with
            % no artefacts would show a filled Step 4 chip in the journey).
            g.step4_ok = g.run_selected && obj.reconstruction_run_complete(run_id);
            % The selected run's own state (running step k, failed at
            % step k, the verdict) is added by reconstruction_update_journey
            if g.state_unconfirmed
                g.step4_note = 'state not confirmed: check the run folder, then Refresh';
            elseif g.cancelling
                g.step4_note = 'cancelling: waiting for the current step to stop';
            elseif g.unavailable_run
                g.step4_note = 'running in a session this app cannot check: cancel it there, or restart the computer';
            elseif g.stale_running
                g.step4_note = 'interrupted: select the run, press Cancel';
            elseif g.active_run
                g.step4_note = 'running: wait, or press Cancel';
            elseif ~g.run_selected && g.no_runs
                g.step4_note = 'no run yet: press Run';
            elseif ~g.run_selected
                g.step4_note = 'no run selected: select one, or press Run';
            elseif g.step4_ok
                g.step4_note = 'done';
            else
                g.step4_note = 'not complete: press Resume';
            end
            g.tools_header_text = 'Edit tools';

            % ---- Run -------------------------------------------------------
            g.run_ok = g.dataset_bound && g.step2_ok && tools_set && ...
                ~g.active_run_or_stale && g.map_ok;
            if ~g.dataset_bound
                g.run_tip = 'Load a dataset first (File > Load file).';
            elseif ~g.step2_ok
                if ~strcmp(obj.reconstruction_sparse_source(), 'built')
                    g.run_tip = 'Choose the sparse model, the reconstruction images and the regions file first.';
                elseif images_set && roi_set
                    g.run_tip = 'Choose the sparse model recipe file first.';
                else
                    g.run_tip = 'Choose the reconstruction images and the regions file first.';
                end
            elseif ~g.tool_state_ok
                g.run_tip = g.tool_state_tip;
            elseif ~tools_set
                g.run_tip = obj.steps_ternary(needs_apde, 'Set all four tool paths first.', 'Set the COLMAP path first.');
            elseif g.state_unconfirmed
                g.run_tip = 'STATE NOT CONFIRMED - check the run folder, then Refresh.';
            elseif g.cancelling
                g.run_tip = 'Cancel is pending; wait for the current step to stop.';
            elseif g.active_run_or_stale
                g.run_tip = 'A run is already active.';
            elseif ~g.map_ok
                g.run_tip = 'Compute an activation map for the loaded dataset (run the OM analysis) first.';
            end

            % ---- Resume ----------------------------------------------------
            % A crash between the manifest write and the tab-state write
            % leaves the MANIFEST RUNNING while tab-state says otherwise. The
            % backend rejects such a resume outright, so the two must not be
            % allowed to disagree here. Read the
            % durable manifest status through the public open_manifest
            % resolver and fail closed on the mismatch.
            manifest_running = obj.reconstruction_manifest_is_running(run_id);
            g.status_drift = manifest_running && ~g.stale_running && ~g.active_run && ...
                ~obj.reconstruction_run_status_is_running(run_id);
            next_stage = '';
            if g.run_selected
                try
                    [ns_ok, ~, next_stage] = obj.reconstruction_tab.next_stage_to_run(run_id);
                catch
                    ns_ok = false;
                    next_stage = '';
                end
                if ~ns_ok
                    next_stage = '';
                end
            end
            need_map = g.run_selected && ~isempty(next_stage);
            g.resume_ok = g.run_selected && ~isempty(next_stage) && ...
                ~g.active_run_or_stale && ~g.status_drift && g.provenance_ok && ...
                (~need_map || g.map_ok);
            if ~g.run_selected
                g.resume_tip = 'Select a run with a pending stage.';
            elseif isempty(next_stage)
                g.resume_tip = sprintf('Run %s has no unfinished step.', run_id);
            elseif g.state_unconfirmed
                g.resume_tip = 'STATE NOT CONFIRMED - check the run folder, then Refresh.';
            elseif g.cancelling
                g.resume_tip = 'Cancel is pending; wait for the current step to stop.';
            elseif g.active_run_or_stale
                g.resume_tip = 'A run is already active.';
            elseif g.status_drift
                g.resume_tip = 'Run is marked RUNNING on disk - refresh, then Cancel it to clear.';
            elseif need_map && ~g.map_ok
                g.resume_tip = 'Resume runs the projection step: load an activation map first.';
            end
            if g.run_selected && ~g.provenance_ok
                g.resume_tip = g.provenance_tip;
            end

            % ---- Cancel / Reproject / Visualise -----------------------------
            % Cancel is only a transient RUNNING request. The pipeline owns
            % durable CANCELLED after run_stage records wrapper exit 130.
            [run_status, durable] = obj.reconstruction_effective_status(run_id);
            if durable && isempty(run_status)
                % The manifest exists but is unreadable: fail closed - never
                % offer a status-corrupting click on an unknown status.
                run_status = '<unreadable>';
            end
            % An uninspectable RUNNING owner, a pending request, or an
            % unconfirmed durable transition must fail closed.
            g.cancel_ok = g.run_selected && ...
                strcmp(run_status, 'RUNNING') && ...
                ~g.unavailable_run && ~g.cancelling && ~g.state_unconfirmed;
            if g.state_unconfirmed
                g.cancel_tip = 'STATE NOT CONFIRMED - check the run folder, then Refresh.';
            elseif g.cancelling
                g.cancel_tip = 'Cancel already requested; waiting for the current step to stop.';
            elseif ~g.cancel_ok
                g.cancel_tip = 'Select a RUNNING run.';
            end
            % A COMPLETED run whose steps all passed, with or without
            % warnings, can have its projection redone
            % (can_redo_reprojection)
            redo_ok = false;
            if g.run_selected && isempty(next_stage) && strcmp(run_status, 'COMPLETED')
                try
                    redo_ok = obj.reconstruction_tab.can_redo_reprojection(run_id);
                catch
                    redo_ok = false;
                end
            end
            g.reproject_ok = g.run_selected && ~g.active_run_or_stale && ...
                ~g.status_drift && g.provenance_ok && g.map_ok && ...
                (strcmp(next_stage, 'reprojection') || redo_ok);
            if ~g.run_selected
                g.reproject_tip = 'Select a run that is waiting for its projection step, or a COMPLETED run.';
            elseif ~strcmp(next_stage, 'reprojection') && ~redo_ok
                g.reproject_tip = ['Redo projection needs a run that is waiting for its projection step, or a ' ...
                    'COMPLETED run whose steps all finished (passed, or passed with warnings).'];
            elseif ~g.map_ok
                g.reproject_tip = 'Load an OM dataset with an activation map first.';
            elseif g.active_run_or_stale
                g.reproject_tip = 'A run is already active.';
            end
            if g.run_selected && ~g.provenance_ok
                g.reproject_tip = g.provenance_tip;
            end
            [vis_ok, ~] = obj.reconstruction_visualise_ready(run_id);
            % Read-only visualisation has its own trust gate. Write/tool
            % readiness remains governed by g.provenance_ok.
            g.visualise_ok = g.run_selected && vis_ok;
            if g.visualise_ok
                g.visualise_tip = '';
            else
                g.visualise_tip = 'Select a run that has outputs to show.';
            end
            if g.run_selected && ~g.provenance_ok
                g.visualise_tip = g.provenance_tip;
            end

            % ---- Step 3 / Citations / runs list -----------------------------
            g.checktools_ok = g.dataset_bound;
            if ~g.dataset_bound
                g.checktools_tip = 'Load a dataset first.';
                g.citations_tip = 'Load a dataset first.';
                g.runlist_tip = 'Load a dataset first.';
            end
            g.citations_ok = g.dataset_bound;
            % The runs list shows nothing without a dataset, and an ENABLED
            % control must not carry a missing-prerequisite tooltip.
            % The empty-state label already covers the no-runs
            % display, so gating on the dataset loses nothing.
            g.runlist_ok = g.dataset_bound;
            g.browse_ok = true;

            % ---- copy-on-write sources --------------------------------------
            % The copy-on-write tools mutate the same run's artefacts the
            % pipeline is writing, so an active run locks every Preview/Apply
            % ("tool Preview/Apply disabled while RUNNING"). Source checks
            % alone would leave the buttons live mid-run.
            src = obj.reconstruction_tool_sources(run_id);
            tools_free = ~g.active_run_or_stale;
            g.touchup_ok = src.mesh && tools_free && g.provenance_ok;
            if ~src.mesh
                g.touchup_tip = 'Select a run with a mesh (projected or rebuilt).';
            elseif ~tools_free
                g.touchup_tip = 'A run is active: its files are being written.';
            end
            if g.run_selected && ~g.provenance_ok
                g.touchup_tip = g.provenance_tip;
            end
            g.intensity_ok = src.fused && tools_free && g.provenance_ok;
            if ~src.fused
                g.intensity_tip = 'Select a run with a fused point cloud.';
            elseif ~tools_free
                g.intensity_tip = 'A run is active: its files are being written.';
            end
            if g.run_selected && ~g.provenance_ok
                g.intensity_tip = g.provenance_tip;
            end
            g.area_ok = src.point_set && tools_free && g.provenance_ok;
            g.area_select_ok = g.area_ok;
            if ~src.point_set
                g.area_tip = 'Select a run with a point cloud.';
            elseif ~tools_free
                g.area_tip = 'A run is active: its files are being written.';
            end
            if g.run_selected && ~g.provenance_ok
                g.area_tip = g.provenance_tip;
            end
            g.smooth_ok = src.projected_mesh && tools_free && g.provenance_ok;
            g.smooth_select_ok = g.smooth_ok;
            if ~src.projected_mesh
                g.smooth_tip = 'Select a run with a mesh.';
            elseif ~tools_free
                g.smooth_tip = 'A run is active: its files are being written.';
            end
            if g.run_selected && ~g.provenance_ok
                g.smooth_tip = g.provenance_tip;
            end
        end

        function g = steps_blank_gate(obj) %#ok<MANU>
            % The gate struct with every field present and falsy, so no
            % consumer ever reads a missing field.
            g = struct('dataset_bound', false, 'restore_mode', false, ...
                'active_run', false, 'stale_running', false, ...
                'unavailable_run', false, 'status_drift', false, ...
                'cancelling', false, 'state_unconfirmed', false, ...
                'active_run_or_stale', false, 'run_selected', false, ...
                'provenance_ok', false, 'provenance_tip', '', ...
                'map_ok', false, 'tool_state_ok', false, 'tool_state_tip', '', ...
                'step1_ok', false, 'step1_note', '', ...
                'step2_ok', false, 'step2_note', '', 'step3_ok', false, ...
                'step3_note', '', 'step3_tip', '', 'step4_ok', false, 'step4_note', '', ...
                'tools_header_text', 'Edit tools', ...
                'no_runs', true, 'run_ok', false, 'resume_ok', false, ...
                'cancel_ok', false, 'reproject_ok', false, ...
                'visualise_ok', false, 'checktools_ok', false, ...
                'citations_ok', false, 'runlist_ok', false, ...
                'browse_ok', true, 'touchup_ok', false, 'intensity_ok', false, ...
                'area_ok', false, 'area_select_ok', false, 'smooth_ok', false, ...
                'smooth_select_ok', false, ...
                'runlist_empty_text', 'No runs yet: press Run to make the first one.', ...
                'run_tip', '', 'resume_tip', '', 'cancel_tip', '', ...
                'reproject_tip', '', 'visualise_tip', '', 'checktools_tip', '', ...
                'citations_tip', '', 'runlist_tip', '', 'browse_tip', '', ...
                'touchup_tip', '', 'intensity_tip', '', 'area_tip', '', ...
                'smooth_tip', '');
        end

        function rows = reconstruction_accordion_rows(obj, open_step, tools_open)
            % Numeric GridLayoutR1.RowHeight (5 rows: four steps + tools).
            % A collapsed row is the 58 px header; an expanded row is the
            % header, the 4 px row spacing and the numeric sum of that
            % panel's content grid (the step panels have no padding).
            % 'fit' appears nowhere - sum() on a cell array throws.
            rows = repmat(58, 1, 5);
            grids = {'GridLayoutS1', 'GridLayoutS2', 'GridLayoutS3', 'GridLayoutS4'};
            if open_step >= 1 && open_step <= 4
                rows(open_step) = 62 + obj.steps_rowtotal(obj.(grids{open_step}));
            end
            if tools_open
                rows(5) = 62 + obj.steps_rowtotal(obj.CopyOnWritePanel);
            end
        end

        function total = steps_rowtotal(obj, h)
            % Sum a grid's declared row heights. MATLAB reads RowHeight back
            % as a CELL vector (verified), so a bare sum() throws
            % MATLAB:sum:wrongInput - normalise first. 'fit' never appears in
            % the run grids, but a non-numeric entry would be a defect, so
            % it is treated as 22 (one standard row) rather than silently
            % dropped.
            % The grid's row spacing and top and bottom padding are added,
            % or the last rows of a tall step are cut off.
            raw = h.RowHeight;
            if ~iscell(raw)
                raw = num2cell(double(raw));
            end
            total = 0;
            for k = 1:numel(raw)
                v = raw{k};
                if isnumeric(v)
                    total = total + double(v);
                else
                    total = total + 22;
                end
            end
            total = total + h.RowSpacing * max(numel(raw) - 1, 0) + h.Padding(2) + h.Padding(4);
        end

        function open_step = reconstruction_step_open(obj)
            % Which step content grid is visible (0 = none).
            open_step = 0;
            grids = {'GridLayoutS1', 'GridLayoutS2', 'GridLayoutS3', 'GridLayoutS4'};
            for k = 1:4
                if strcmp(obj.(grids{k}).Visible, 'on')
                    open_step = k;
                end
            end
        end

        function tf = reconstruction_tools_open(obj)
            tf = isprop(obj, 'CopyOnWritePanel') && strcmp(obj.CopyOnWritePanel.Visible, 'on');
        end

        function reconstruction_set_accordion(obj, open_step, tools_open)
            % Apply Visible and the parent RowHeight together: a hidden child
            % grid does not shrink its parent row (verified by execution).
            % The five writes are literal statements on purpose: a test
            % reads this method's TEXT, so a write made through a dynamic
            % field name would be invisible to it and would fail its
            % completeness check for new controls.
            obj.GridLayoutS1.Visible = obj.steps_pick(open_step == 1);
            obj.GridLayoutS2.Visible = obj.steps_pick(open_step == 2);
            obj.GridLayoutS3.Visible = obj.steps_pick(open_step == 3);
            obj.GridLayoutS4.Visible = obj.steps_pick(open_step == 4);
            obj.CopyOnWritePanel.Visible = obj.steps_pick(tools_open);
            obj.GridLayoutR1.RowHeight = obj.reconstruction_accordion_rows(open_step, tools_open);
        end

        function tf = reconstruction_map_matches_dataset(obj)
            % Identity rule: the activation map must belong to the
            % LOADED dataset (stem match), not merely be non-empty. A further
            % dataset folder (<stem>_01.matom) belongs to the recording <stem>.
            tf = false;
            if isempty(obj.reconstruction_tab) || isempty(obj.host.processed_data.activation_map)
                return;
            end
            if isempty(obj.host.file_info.path) || isempty(obj.host.file_info.name)
                return;
            end
            [~, stem] = fileparts(obj.host.file_info.name);
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            tf = strcmp(stem, rabbit_reconstruction_tab.recording_stem(ds_root, ds_stem));
        end

        function [ok, err, info] = reconstruction_validate_manifest_provenance(obj, run_id)
            % Re-read the selected run's active manifest at click time. A
            % direct-v2-only run, or a v2 whose manifest.json sibling cannot
            % be read, is inspection-only: no Resume, Reproject, or
            % copy-on-write edit may proceed from that provenance.
            ok = false;
            err = '';
            info = struct();
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                err = 'No reconstruction run is selected.';
                return;
            end
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', ...
                'runs', run_id);
            v1 = fullfile(run_dir, 'manifest.json');
            v2 = fullfile(run_dir, 'manifest.v2.json');
            if exist(v1, 'file')
                manifest_path = v1;
            elseif exist(v2, 'file')
                manifest_path = v2;
            else
                err = sprintf('Run %s has no readable manifest.json or manifest.v2.json.', run_id);
                return;
            end
            try
                [open_ok, open_err, info] = obj.reconstruction_tab.open_manifest(manifest_path);
            catch ME
                open_ok = false;
                open_err = ME.message;
            end
            if ~open_ok
                if exist(v2, 'file')
                    err = sprintf(['Run %s cannot be checked: its run record is unverified, ' ...
                        'because its manifest.json cannot be read (%s).'], run_id, open_err);
                else
                    err = sprintf('Run %s cannot be checked: %s', run_id, open_err);
                end
                return;
            end
            if isfield(info, 'unverified_provenance') && info.unverified_provenance
                kind = '';
                if isfield(info, 'open_kind') && ~isempty(info.open_kind)
                    kind = [' (' char(info.open_kind) ')'];
                end
                err = sprintf(['Run %s can only be viewed: its run record is unverified%s, as there ' ...
                    'is no matching manifest.json. Open it again with its manifest.json to resume or edit it.'], run_id, kind);
                return;
            end
            ok = true;
        end

        function [ok, note] = reconstruction_provenance_state(obj, run_id)
            % Gate-facing wrapper around the same click-time validator.
            [ok, err] = obj.reconstruction_validate_manifest_provenance(run_id);
            if ok
                note = '';
            elseif isempty(err)
                note = 'The run record could not be checked.';
            else
                note = err;
            end
        end
        function status = reconstruction_manifest_status(obj, run_id)


            % The durable manifest's validated result.status, or '' when
            % unreadable/invalid. Never return a numeric, object or unknown
            % enum: callers are allowed to use strcmp and sprintf directly.
            % Read-only. Both native manifest.v2.json and manifest.json are
            % considered; the backend resolver decides which source is
            % authoritative when both exist (including stale-sidecar fallback).
            status = '';
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', ...
                'runs', run_id);
            v2 = fullfile(run_dir, 'manifest.v2.json');
            v1 = fullfile(run_dir, 'manifest.json');
            if exist(v2, 'file')
                mp = v2;
            elseif exist(v1, 'file')
                mp = v1;
            else
                return;
            end
            try
                [ok, ~, info] = obj.reconstruction_tab.open_manifest(mp);
                if ok && isstruct(info) && isscalar(info) && isfield(info, 'result_status')
                    [status_ok, candidate] = obj.steps_run_status_text(info.result_status);
                    if status_ok
                        status = candidate;
                    end
                end
            catch
                status = '';
            end
        end

        function tf = reconstruction_manifest_is_running(obj, run_id)
            % The durable manifest's result.status == 'RUNNING'. Read through
            % the public open_manifest resolver, never a private path: a
            % crash-cut can leave this RUNNING while tab-state disagrees.
            tf = false;
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            tf = strcmp(obj.reconstruction_manifest_status(run_id), 'RUNNING');
        end

        function tf = reconstruction_run_status_is_running(obj, run_id)
            tf = strcmp(obj.reconstruction_run_status(run_id), 'RUNNING');
        end

        function tf = reconstruction_run_complete(obj, run_id)
            % A run is COMPLETE for journey purposes when the durable
            % manifest says COMPLETED and its visualisation artefacts resolve
            % and parse. The durable status is the authority (reading
            % tab-state here would let a FAILED manifest render as a
            % completed step while Cancel, which reads the manifest,
            % disagrees).
            tf = false;
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            [status, durable] = obj.reconstruction_effective_status(run_id);
            if ~durable || ~strcmp(status, 'COMPLETED')
                % Only the durable manifest can claim completion.
                return;
            end
            [vis_ok, ~] = obj.reconstruction_visualise_ready(run_id);
            tf = vis_ok;
        end

        function [status, durable] = reconstruction_effective_status(obj, run_id)
            % The one per-run status used by every consumer (journey, run
            % list, completion, Cancel/Resume/Reproject).
            %   status  - the durable manifest's status when the manifest
            %             EXISTS; else the tab-state status (a run with no
            %             manifest on disk yet is a legitimate fresh case).
            %   durable - true when `status` came from the manifest.
            % A manifest that exists but cannot be read must not silently
            % fall back to tab-state for status-sensitive claims: the
            % caller sees durable=true with an empty
            % status and can fail closed.
            status = '';
            durable = false;
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            mp_exists = obj.reconstruction_manifest_exists(run_id);
            if mp_exists
                durable = true;
                status = obj.reconstruction_manifest_status(run_id);
                return;
            end
            status = obj.reconstruction_run_status(run_id);
        end

        function tf = reconstruction_manifest_exists(obj, run_id)
            tf = false;
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', ...
                'runs', run_id);
            tf = exist(fullfile(run_dir, 'manifest.json'), 'file') > 0 || ...
                exist(fullfile(run_dir, 'manifest.v2.json'), 'file') > 0;
        end

        function status = reconstruction_run_status(obj, run_id)
            % The selected run's validated tab-state status ('' when absent).
            status = '';
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            runs = obj.reconstruction_validated_runs();
            for k = 1:numel(runs)
                if strcmp(runs(k).id, run_id)
                    status = runs(k).status;
                    return;
                end
            end
        end

        function [ok, vis_present] = reconstruction_visualise_ready(obj, run_id)
            % Never throws: this runs on every repaint, so a malformed
            % artefact must degrade to "not ready", not to an error dialog.
            % All failures are caught below.
            % Uses resolve_visualisation_context and visualisation_panel_model
            % to support intermediate runs where geometry is ready, while
            % strictly failing closed if any claimed artifact is missing
            % or incompatible (probe_restore_gui_safety).
            ok = false;
            vis_present = false;
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            try
                [exist_ok, ~, vis] = obj.reconstruction_tab.resolve_visualisation_context(run_id);
            catch
                return;
            end
            if ~exist_ok || ~isstruct(vis) || ~isscalar(vis)
                return;
            end
            % An intermediate run has empty paths; a path of any other type
            % than text is malformed
            names = {'fused_ply', 'rebuilt_ply', 'projected_ply'};
            for k = 1:numel(names)
                if ~isfield(vis, names{k})
                    return;
                end
                v = vis.(names{k});
                if ~(ischar(v) || (isstring(v) && isscalar(v) && ~ismissing(v)))
                    return;
                end
            end
            try
                [model_ok, ~, panels] = obj.reconstruction_tab.visualisation_panel_model(vis);
            catch
                return;
            end
            if ~model_ok
                return;
            end
            vis_present = any(strcmp({panels.render_status}, 'READY'));
            % A trusted run with zero READY panels is still visualisable as a
            % three-panel diagnostic placeholder figure.
            % Digest anomalies remain hard blockers even though trusted
            % missing and parser-level incompatible panels render read-only.
            try
                [anom, ~] = obj.anomalous_views(vis);
            catch
                return;
            end
            if anom
                return;
            end
            ok = true;
        end

        function src = reconstruction_tool_sources(obj, run_id)
            %Shared source gate: use the same operation-specific
            %descriptor hook that Preview/Apply records, rather than a
            %generic current-source flag or a second precedence table.
            %One flag per tool: fused = Intensity, point_set = Area,
            %mesh = Touch-up, projected_mesh = Smooth. These are
            %deliberately not collapsed into one source.
            src = struct('point_set', false, 'fused', false, ...
                'mesh', false, 'projected_mesh', false);
            if isempty(obj.reconstruction_tab) || isempty(run_id)
                return;
            end
            try
                [ok, ~, d] = obj.reconstruction_tab.edit_source_descriptor(run_id, 'intensity');
                src.fused = ok && d.admissible;
            catch
            end
            try
                [ok, ~, d] = obj.reconstruction_tab.edit_source_descriptor(run_id, 'touchup');
                src.mesh = ok && d.admissible;
            catch
            end
            try
                [ok, ~, d] = obj.reconstruction_tab.edit_source_descriptor(run_id, 'area');
                src.point_set = ok && d.admissible;
            catch
            end
            try
                [ok, ~, d] = obj.reconstruction_tab.edit_source_descriptor(run_id, 'smooth');
                src.projected_mesh = ok && d.admissible;
            catch
            end
        end

        function s = steps_step_text(obj, n, done, note) %#ok<INUSL>
            % One header's text: "n  <name> <dash> <state>". The state
            % (status and the next action when unfinished) is carried by
            % `note`, computed from the gate.
            titles = {'Data', 'Inputs', 'Tools', 'Run'};
            s = sprintf('%d  %s %s %s', n, titles{n}, char(8212), note);
        end

        function c = primary_colour(obj) %#ok<MANU>
            % Background of the main action of a group (Run, Visualise)
            c = [0.00 0.37 0.72];
        end

        function reconstruction_edge_weight_changed(obj)
            % The edge weight field: RHYTHM's value is the default; another
            % value is marked "changed" (label, pale amber field, tooltip),
            % as the run records it as a deviation
            rhythm = rabbit_rhythm_reproject.MIN_EDGE_EDGE;
            v = obj.ReconstructionEdgeWeightField.Value;
            base = sprintf('Edge weight (RHYTHM %.2f)', rhythm);
            tip = {['Projection (RHYTHM): faces that no camera sees directly, e.g. on the rim, take the views ' ...
                'whose edge weight is at least this.']; ...
                sprintf(['RHYTHM %.2f (default). Lower fills more of the rim with edge-on data; the faces it ' ...
                'adds are low-confidence (Results gives their number). Read by Run, Resume and Redo projection.'], rhythm)};
            if abs(v - rhythm) > 1e-9
                obj.ReconstructionEdgeWeightLabel.Text = [base ' ' char(8212) ' changed'];
                obj.ReconstructionEdgeWeightField.BackgroundColor = [1.00 0.93 0.75];
                obj.ReconstructionEdgeWeightField.Tooltip = [{sprintf(['Changed from RHYTHM''s %.2f ' char(8212) ...
                    ' recorded as a deviation.'], rhythm)}; tip];
            else
                obj.ReconstructionEdgeWeightLabel.Text = base;
                obj.ReconstructionEdgeWeightField.BackgroundColor = [1 1 1];
                obj.ReconstructionEdgeWeightField.Tooltip = tip;
            end
        end

        function run_dir = reconstruction_selected_run_dir(obj)
            % The selected run's folder ('' when no run is selected)
            run_dir = '';
            run_id = obj.reconstruction_selected_run_id();
            if isempty(run_id) || isempty(obj.reconstruction_tab), return; end
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', 'runs', run_id);
            if ~isfolder(run_dir), run_dir = ''; end
        end

        function reconstruction_update_run_folder_button(obj)
            % Open run folder: on for a selected run; its tooltip names the
            % run's main output files (the tab does not show their paths)
            run_dir = obj.reconstruction_selected_run_dir();
            obj.ReconstructionOpenRunFolderButton.Enable = obj.steps_pick(~isempty(run_dir));
            if isempty(run_dir)
                obj.ReconstructionOpenRunFolderButton.Tooltip = {'Select a run first.'};
                return;
            end
            tip = {['Open the folder of run ' obj.reconstruction_selected_run_id() ':']; run_dir};
            names = {'Dense cloud', 'outputs', 'fused-geometric.ply'; 'Mesh', 'outputs', 'mesh-cleanup.ply'; ...
                'Projected activation', fullfile('outputs', 'reprojection'), 'activation_projected.ply'};
            for k = 1:size(names, 1)
                if exist(fullfile(run_dir, names{k, 2}, names{k, 3}), 'file') == 2
                    tip{end + 1, 1} = sprintf('%s: %s', names{k, 1}, fullfile(names{k, 2}, names{k, 3})); %#ok<AGROW>
                end
            end
            obj.ReconstructionOpenRunFolderButton.Tooltip = tip;
        end

        function reconstruction_open_run_folder(obj)
            % Open run folder: the selected run's folder in the system's file browser
            run_dir = obj.reconstruction_selected_run_dir();
            if isempty(run_dir)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run first.', 'Open run folder');
                return;
            end
            rabbit_reconstruction_ui.open_folder(run_dir);
        end

        function s = steps_pick(obj, b) %#ok<MANU>
            % Boolean -> the uicontrol enable/visible token.
            if b
                s = 'on';
            else
                s = 'off';
            end
        end

        function out = steps_ternary(obj, cond, a, b) %#ok<MANU>
            if cond
                out = a;
            else
                out = b;
            end
        end
        function lines = reconstruction_results_details(obj, run_id)
            % Details...: the selected run's full text, as the Results box
            % gave it before the verdict rows: status, the file check, the
            % projection check in words and the units
            lines = {};
            if isempty(run_id) || isempty(obj.reconstruction_tab), return; end
            run_dir = obj.reconstruction_selected_run_dir();
            [is_clean, ~] = obj.reconstruction_tab.reconstruction_completion_consistency(run_id);
            m = obj.reconstruction_tab.read_manifest(run_dir);
            status = '';
            if isstruct(m) && isfield(m, 'result') && isfield(m.result, 'status'), status = char(m.result.status); end
            lines = {sprintf('Run %s status: %s.', run_id, status)};
            if ~isempty(is_clean) && islogical(is_clean) && is_clean
                % The check covers these three files only; the viewer shows
                % more panels
                lines{end + 1} = ['Clean completion verified: every step finished, and the three files this check ' ...
                    'covers (COLMAP dense cloud, mesh, projected activation) are present and unchanged since they were ' ...
                    'written; the viewer''s other panels are not part of it.'];
            end
            lines = [lines, obj.reconstruction_projection_lines(m, obj.reconstruction_tab.run_row_views(run_dir), run_dir), ...
                obj.reconstruction_tab.metric_lines(run_dir)];
            r = obj.reconstruction_tab.run_report(run_id);
            if r.ok
                lines{end + 1} = r.defect.line;
                for k = 1:numel(r.stages)
                    if ~strcmp(r.stage_status{k}, 'WARNED'), continue; end
                    w = obj.reconstruction_tab.step_warning_lines(run_id, r.stages{k});
                    lines{end + 1} = sprintf('Step %d, %s, passed with warnings:', k, ...
                        obj.reconstruction_stage_label(r.stages{k}, r.stages)); %#ok<AGROW>
                    lines = [lines, strcat({'  '}, w)]; %#ok<AGROW>
                end
            end
            lines = rabbit_reconstruction_tab.display_paths_in(lines);   % one separator style
        end

        function reconstruction_update_results_buttons(obj, run_id)
            % Why? only for a run the defect rule marks; Details...
            % for any selected run
            verdict = '';
            if ~isempty(run_id) && ~isempty(obj.reconstruction_tab)
                try
                    r = obj.reconstruction_tab.run_report(run_id);
                    verdict = r.verdict;
                catch
                end
            end
            obj.ReconstructionWhyButton.Visible = obj.steps_pick(strcmp(verdict, 'DO_NOT_USE'));
            obj.ReconstructionDetailsButton.Enable = obj.steps_pick(~isempty(run_id));
        end

        function reconstruction_show_why(obj)
            % Why?: the defect rule and this run's values, from its record
            run_id = obj.reconstruction_selected_run_id();
            if isempty(run_id), return; end
            r = obj.reconstruction_tab.run_report(run_id);
            d = r.defect;
            cov = 'not recorded';
            if d.cover_found
                % d.cover is in view order, View1 to View4 (run_defect_rule)
                cov = strjoin(arrayfun(@(k) sprintf('View%d %.0f %%', k, 100 * d.cover(k)), 1:numel(d.cover), ...
                    'UniformOutput', false), ', ');
            end
            % Coverage first, then M7, as the reason; titled with the one
            % term, NOT FOR ANALYSIS. The one verdict sentence first, as
            % Results, Step 4, Visualise and the saved footers say it
            msg = sprintf(['%s\n\nThe defect rule (Help > Limitations and checks) calls a run defective when the ' ...
                'mesh covers less than %.0f %% of the heart in some OM view and the mesh fit check (M7) warned.\n\n' ...
                'This run: mesh coverage by view: %s, from the projection check; mesh fit (M7) %s, from the mesh ' ...
                'step''s check record.'], d.line, 100 * d.limit, cov, obj.steps_ternary(d.m7_found, d.m7_verdict, 'not recorded'));
            uialert(obj.host.opticalmappingUIFigure, msg, 'NOT FOR ANALYSIS', 'Icon', 'warning');
        end

        function reconstruction_show_details(obj)
            % Details...: the selected run's full text in a window of its own
            run_id = obj.reconstruction_selected_run_id();
            lines = obj.reconstruction_results_details(run_id);
            if isempty(lines), lines = {'Select a run first.'}; end
            obj.reconstruction_text_window(sprintf('Run %s', run_id), lines);
        end

        function reconstruction_text_window(obj, name, lines)
            % A window that shows lines of text, large and wrapped
            scr = get(groot, 'ScreenSize');
            w = min(1100, scr(3) - 80);
            h = min(720, scr(4) - 120);
            vis = obj.steps_ternary(strcmp(getenv('OM_APP_HEADLESS'), '1'), 'off', 'on');
            fig = uifigure('Name', name, 'Visible', vis, ...
                'Position', [max(40, (scr(3) - w) / 2), max(60, (scr(4) - h) / 2), w, h]);
            gl = uigridlayout(fig, [1 1]);
            uitextarea(gl, 'Value', lines, 'Editable', 'off');   % a text area wraps its lines
        end

        function reconstruction_restore_summary(obj, info)
            % A few lines around the opened run's status lines: what was
            % opened, any problem, and what is needed next
            lines = obj.ReconstructionResultsText.Value;
            if ischar(lines), lines = {lines}; end
            % The run's folder is named, and a recording loaded from another
            % folder is said: the header and image stay that recording's
            ds_dir = '';
            if isfield(info, 'dataset_root') && ~isempty(info.dataset_root), ds_dir = char(info.dataset_root); end
            lines = [{sprintf('Opened saved run %s of %s (in %s).', info.run_id, info.dataset_stem, ds_dir)}, lines(:)'];
            try
                loaded = obj.host.file_info.path;
                if ischar(loaded) && ~isempty(loaded) && ~isempty(ds_dir) && ~rabbit_stack_io.same_file(loaded, ds_dir)
                    lines{end+1} = sprintf(['The recording loaded now (%s) is from another folder: the header and ' ...
                        'the image are that recording''s, the Reconstruction tab shows the run''s dataset in %s.'], ...
                        fullfile(obj.host.file_info.path, obj.host.file_info.file), ds_dir);
                end
            catch
            end
            if isfield(info, 'dataset_path_mismatch') && info.dataset_path_mismatch
                lines{end+1} = 'The run has been moved or copied since it was made; it is read from its current folder.';
            end
            if isfield(info, 'sidecar_warning') && ~isempty(info.sidecar_warning)
                lines{end+1} = info.sidecar_warning;
            end
            if isfield(info, 'open_warning') && ~isempty(info.open_warning)
                lines{end+1} = info.open_warning;
            end
            if isfield(info, 'unverified_provenance') && info.unverified_provenance
                lines{end+1} = ['UNVERIFIED RUN RECORD: view only, as manifest.json is missing or unreadable. ' ...
                    'Resume, Redo projection and the edit tools stay off until you open the run with its manifest.json.'];
            end
            % A built run holds its own sparse model and images, wherever
            % the run folder now is
            built = isfield(info, 'run_dir') && ~isempty(info.run_dir) && ...
                isfolder(fullfile(info.run_dir, 'stages', 'sparse_build', 'model'));
            if ~built
                lines{end+1} = ['Still required: choose the sparse model and image folder again before a step ' ...
                    'that needs them (the run did not record where they were).'];
            end
            if isempty(info.next_stage) && isfield(info, 'result_status') && strcmp(info.result_status, 'COMPLETED')
                lines{end+1} = 'Next: press Visualise to look at the results.';
            end
            lines{end+1} = 'To redo the projection, load the recording first: opening a run does not load its activation map.';
            obj.ReconstructionResultsText.Value = lines;
        end

        function reconstruction_auto_visualise(obj, info)
            % Render the validated views READ-ONLY.
            % Failures are non-fatal: the session stays committed and the
            % exact failure list is reported (never a rollback).
            if ~isfield(info, 'active_manifest_path')
                obj.VisualiseStatusText.Value = {'Automatic visualisation unavailable: no active manifest.'};
                return;
            end
            % UNVERIFIED provenance (a v2-only sidecar, or
            % a v2 whose sibling is unreadable) is READ-ONLY inspection only:
            % the automatic render is suppressed until the
            % operator acknowledges the unverified provenance.
            if isfield(info, 'unverified_provenance') && info.unverified_provenance
                obj.VisualiseStatusText.Value = {sprintf(['Run %s: not shown automatically, as its run ' ...
                    'record is unverified (see Results).'], info.run_id)};
                return;
            end
            % A run whose 3-PLY gate was exempted (CREATED/RUNNING
            % partial runs) must not attempt to render absent PLYs.
            if isfield(info, 'partial_exempt') && info.partial_exempt
                obj.VisualiseStatusText.Value = {sprintf('Run %s: visualisation deferred until the run has its outputs.', ...
                    info.run_id)};
                return;
            end
            % Read the ACTIVE source's status (the v1 literal is
            % never consulted for the RUNNING gate).
            [st_ok, status] = obj.reconstruction_active_status(info);
            if st_ok && strcmp(status, 'RUNNING')
                obj.VisualiseStatusText.Value = {sprintf(['Run %s is running in another app or MATLAB ' ...
                    'session: visualisation deferred.'], info.run_id)};
                return;
            end
            % ANOMALOUS-class views are not auto-rendered:
            % a view artefact whose recorded sha256 is a real 64-hex
            % digest that MISMATCHES the file on disk is provenance-broken;
            % rendering it automatically would display data the manifest
            % itself cannot vouch for. The render is suppressed and the
            % anomaly is reported (there is no acknowledgement dialog).
            [anom, anom_list] = obj.anomalous_views(info);
            if anom
                obj.VisualiseStatusText.Value = {sprintf(['Not shown automatically: %s changed after ' ...
                    'the run recorded it.'], anom_list)};
                return;
            end
            [ok, err, figs] = obj.visualise_artifacts_handle(info);
            if ~ok
                obj.VisualiseStatusText.Value = {sprintf('Run opened, but visualisation failed: %s', err)};
                return;
            end
            if ~isempty(figs)
                obj.VisualiseStatusText.Value = {sprintf('Run %s visualised in figure %d.', info.run_id, figs(1).Number)};
            else
                obj.VisualiseStatusText.Value = {sprintf('Run %s: automatic visualisation produced no figures.', info.run_id)};
            end
        end

        function [ok, status] = reconstruction_active_status(obj, info)
            % The active manifest's result.status ('' when unavailable).
            ok = false; status = '';
            try
                m = obj.reconstruction_tab.read_manifest(info.run_dir);
                if isstruct(m) && isfield(m, 'result') && isfield(m.result, 'status')
                    status = char(m.result.status);
                    ok = true;
                end
            catch
                ok = false;
            end
        end

        function [ok, err, figure_handles] = visualise_artifacts_handle(obj, info)
            %VISUALISE_ARTIFACTS_HANDLE App-side auto-visualise hook.
            %Both automatic and manual entry resolve the same validated active
            %manifest context; neither reads a sibling sidecar directly.
            ok = false; err = ''; figure_handles = [];
            % Test seam: test_visualise_fails (probe_restore_and_visualise_gui)
            if isprop(obj, 'test_visualise_fails') && ~isempty(obj.test_visualise_fails)
                err = 'analyse_om:Reconstruction:TestInjected:visualise_artifacts_handle';
                return;
            end
            % Test seam: test_visualise_empty (probe_restore_gui_safety)
            if isprop(obj, 'test_visualise_empty') && obj.test_visualise_empty
                ok = true;
                return;
            end
            [ctx_ok, ctx_err, vis] = obj.reconstruction_tab.resolve_visualisation_context(info.run_id);
            if ~ctx_ok
                err = ctx_err;
                return;
            end
            [ok, err, fig] = obj.reconstruction_tab.visualise_artifacts(vis);
            if ok && ~isempty(fig)
                figure_handles = fig;
            end
        end

        function [anom, list] = anomalous_views(obj, info)
            %ANOMALOUS_VIEWS True when a view's recorded digest is a real
            %hex digest that mismatches the file.
            anom = false; list = '';
            try
                m = obj.reconstruction_tab.read_manifest(info.run_dir);
            catch
                return;
            end
            if ~isstruct(m), return; end
            % The mesh row is named after the file actually shown
            [~, mesh_name, mesh_ext] = fileparts(info.rebuilt_ply);
            views = {'fused-geometric.ply', info.fused_ply; ...
                     [mesh_name mesh_ext], info.rebuilt_ply; ...
                     'activation_projected.ply', info.projected_ply};
            recs = obj.digest_records(m);
            for k = 1:size(views, 1)
                nm = views{k, 1}; path = views{k, 2};
                if isempty(path) || ~exist(path, 'file'), continue; end
                dg = '';
                % Match the recorded path exactly first, then by
                % Basename. A moved/copied run rebases `path` into the new
                % run dir while the manifest still records the archive-time
                % absolute path; without the basename fallback the gate
                % false-negatives for exactly that class and a replaced view
                % would render unverified.
                for j = 1:numel(recs)
                    if strcmp(recs(j).path, path)
                        dg = recs(j).sha256;
                        break;
                    end
                end
                if isempty(dg)
                    % Compare basenames (name + extension on
                    % Both sides). The first version compared [have ext]
                    % against the NAME only, which can never be true -- the
                    % fallback was dead code and a replaced view in a
                    % moved/copied run rendered unverified.
                    [~, want_name, want_ext] = fileparts(path);
                    want = [want_name want_ext];
                    for j = 1:numel(recs)
                        [~, have, ext] = fileparts(recs(j).path);
                        if strcmp([have ext], want)
                            dg = recs(j).sha256;
                            break;
                        end
                    end
                end
                if isempty(dg) || isempty(regexp(dg, '^[0-9a-f]{64}$', 'once'))
                    continue; % hash-unavailable NORMAL class -> no gate
                end
                [~, hex, ~] = obj.reconstruction_tab.manifest_bytes_sha256(path);
                if ~isempty(hex) && ~strcmpi(hex, dg)
                    anom = true;
                    if isempty(list), list = nm; else, list = [list ', ' nm]; end
                end
            end
        end

        function recs = digest_records(obj, m)
            %Collect (path, sha256) pairs from stage artifacts + result block.
            recs = struct('path', {}, 'sha256', {});
            if isfield(m, 'stages') && isstruct(m.stages)
                for k = 1:numel(m.stages)
                    if ~isfield(m.stages(k), 'artifacts'), continue; end
                    a = m.stages(k).artifacts;
                    if isstruct(a) && isfield(a, 'path')
                        for j = 1:numel(a)
                            e = struct('path', char(a(j).path), 'sha256', '');
                            if isfield(a(j), 'sha256') && ischar(a(j).sha256)
                                e.sha256 = a(j).sha256;
                            end
                            recs(end+1) = e;
                        end
                    end
                end
            end
            if isfield(m, 'result') && isstruct(m.result) && ...
                    isfield(m.result, 'reprojection') && isstruct(m.result.reprojection)
                rp = m.result.reprojection;
                if isfield(rp, 'ply'), recs(end+1) = struct('path', char(rp.ply), 'sha256', ''); end
            end
        end

        function s = value_or_none(obj, x)
            if isempty(x)
                s = '(none - all steps finished)';
            else
                s = x;
            end
        end

        function reconstruction_refresh(obj, dataset_stem)
            % Binds the dataset root/stem from the loaded file and loads
            % the tab-state JSON. Called from load_selected_file
            % and at startup (no dataset -> empty state).
            % dataset_stem (optional): a further dataset folder of the
            % recording, <stem>_01; default the recording's own <stem>.matom
            if isempty(obj.host.file_info.path) || isempty(obj.host.file_info.name)
                obj.ReconstructionDatasetField.Value = '';
                obj.ReconstructionRunList.Items = {};
                obj.reconstruction_edit_reset_state();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                obj.reconstruction_edit_refresh();
                obj.reconstruction_update_dataset_folders();
                obj.reconstruction_show_cv_scale();
                return;
            end
            [~, stem] = fileparts(obj.host.file_info.name);
            if nargin >= 2
                stem = dataset_stem;
            end
            obj.ReconstructionDatasetField.Value = fullfile(obj.host.file_info.path, [stem '.matom']);
            obj.reconstruction_restore_mode = false;
            obj.reconstruction_edit_reset_state();
            obj.reconstruction_tab = rabbit_reconstruction_tab();
            try
                [ok, err] = obj.reconstruction_tab.load_state(obj.host.file_info.path, stem);
            catch load_err
                ok = false;
                err = ['The reconstruction state could not be loaded: ' load_err.message];
            end
            if ~ok
                % Do not stay half-bound.
                obj.reconstruction_tab = [];
                obj.ReconstructionDatasetField.Value = '';
                obj.ReconstructionRunList.Items = {};
                obj.reconstruction_edit_reset_state();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
                obj.reconstruction_update_dataset_folders();
                obj.reconstruction_show_cv_scale();
                uialert(obj.host.opticalmappingUIFigure, err, 'Reconstruction state');
                return;
            end
            % Populate the tool-path fields: typed this session, else the
            % dataset's saved path, else the last used path, else OM_*.
            s = obj.reconstruction_tab.get_state();
            obj.reconstruction_show_tool_paths(s);
            [sync_ok, sync_err] = obj.reconstruction_sync_tool_paths();
            obj.reconstruction_restore_sfm_choice(s);
            obj.reconstruction_restore_step2_inputs(s);
            obj.reconstruction_update_run_list();
            obj.reconstruction_list_new_run_steps();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            if ~sync_ok
                obj.StepHeader3.Text = obj.steps_step_text(3, false, 'check failed: see message');
                obj.StepHeader3.Tooltip = {['Check tools failed: ' sync_err]};
            end
            obj.reconstruction_edit_refresh();
            % Older run records (set aside as legacy_runs): say so once in
            % Results, so an empty Runs list is not a surprise
            note = obj.reconstruction_tab.get_state_notice();
            if ~isempty(note)
                obj.ReconstructionResultsText.Value = {note};
            end
            obj.reconstruction_update_dataset_folders();
            obj.reconstruction_show_cv_scale();
        end

        function reconstruction_show_cv_scale(obj)
            % The Conduction Velocity tab's scale line and its Scale from
            % calibration... button, for the recording loaded now
            try
                rabbit_calibration_scale.show(obj.host);
                rabbit_cv_map.controls(obj.host);   % smoothing and the two-frame time window
            catch
                % a test double without the Conduction Velocity tab
            end
        end

        function [root, recording, folder] = reconstruction_dataset_names(obj)
            % The bound dataset as parts: its root, the recording it belongs
            % to, and the folder name without .matom. Empty when no
            % dataset is bound.
            root = '';
            recording = '';
            folder = '';
            ds = obj.ReconstructionDatasetField.Value;
            if isempty(ds), return; end
            [root, folder] = fileparts(ds);
            recording = rabbit_reconstruction_tab.recording_stem(root, folder);
        end

        function tf = reconstruction_dataset_choice_ok(obj)
            % Dataset folders can be switched for the recording that is
            % loaded, not for a run opened from a manifest on its own
            tf = false;
            [root, recording] = obj.reconstruction_dataset_names();
            if isempty(root) || isempty(obj.reconstruction_tab) || ...
                    isempty(obj.host.file_info.path) || isempty(obj.host.file_info.name)
                return;
            end
            [~, loaded] = fileparts(obj.host.file_info.name);
            tf = strcmp(loaded, recording) && rabbit_stack_io.same_file(root, obj.host.file_info.path);
        end

        function reconstruction_update_dataset_folders(obj)
            % List the recording's dataset folders in Step 1, and the next
            % new one once the bound folder has runs
            dd = obj.ReconstructionDatasetFolderDropDown;
            [root, recording, folder] = obj.reconstruction_dataset_names();
            if isempty(root)
                dd.Items = {'-'};
                dd.ItemsData = {''};
                dd.Value = '';
                dd.Enable = 'off';
                return;
            end
            stems = rabbit_reconstruction_tab.dataset_stems(root, recording);
            if ~any(strcmp(stems, folder))
                stems{end + 1} = folder;
            end
            items = cell(size(stems));
            any_runs = false;
            for k = 1:numel(stems)
                n = rabbit_reconstruction_tab.dataset_run_count(root, stems{k});
                any_runs = any_runs || n > 0;
                items{k} = sprintf('%s.matom (%d run%s)', stems{k}, n, obj.steps_ternary(n == 1, '', 's'));
            end
            data = stems;
            if any_runs && obj.reconstruction_dataset_choice_ok()
                next_stem = rabbit_reconstruction_tab.next_dataset_stem(root, recording);
                items{end + 1} = sprintf('Start new folder: %s.matom', next_stem);
                data{end + 1} = next_stem;
            end
            dd.ItemsData = {};
            dd.Items = items;
            dd.ItemsData = data;
            dd.Value = folder;
            dd.Enable = obj.steps_pick(obj.reconstruction_dataset_choice_ok() && numel(data) > 1);
        end

        function reconstruction_dataset_folder_changed(obj)
            % Step 1: switch to another dataset folder of this recording,
            % or start the new one. Earlier runs are not changed or moved.
            dd = obj.ReconstructionDatasetFolderDropDown;
            chosen = dd.Value;
            [~, ~, folder] = obj.reconstruction_dataset_names();
            if strcmp(chosen, folder), return; end
            if ~obj.reconstruction_assert_no_active_run()
                dd.Value = folder;
                return;
            end
            obj.reconstruction_bind_dataset(chosen);
        end

        function s = reconstruction_activation_restore_for(obj, run_id)
            % The restored activation state, only for the run it came from;
            % it must never be written into another run's record
            s = struct();
            if strcmp(obj.activation_restore_run_id, run_id)
                s = obj.activation_restore_state;
            end
        end

        function reconstruction_bind_dataset(obj, dataset_stem)
            % Bind a dataset folder of the loaded recording. A new folder
            % starts with what is on the screen in Step 2, so the run set up
            % there can go ahead.
            [root] = obj.reconstruction_dataset_names();
            is_new = ~isfolder(fullfile(root, [dataset_stem '.matom']));
            source = obj.ReconstructionSparseSourceDropDown.Value;
            recipe = obj.ReconstructionSfmRecipeDropDown.Value;
            file = obj.reconstruction_sfm_recipe_file;
            calibration = obj.ReconstructionCalibrationDropDown.Value;
            % State held for a run of the folder being left does not apply here
            obj.unconfirmed_run_id = '';
            obj.activation_restore_state = struct();
            obj.activation_restore_run_id = '';
            obj.reconstruction_refresh(dataset_stem);
            if is_new && ~isempty(obj.reconstruction_tab)
                obj.ReconstructionSparseSourceDropDown.Value = source;
                obj.ReconstructionSfmRecipeDropDown.Value = recipe;
                obj.reconstruction_sfm_recipe_file = file;
                obj.reconstruction_show_sparse_source();
                % Calibrations belong to the recording, so a new dataset
                % folder keeps the one chosen
                obj.reconstruction_refresh_calibrations();
                if any(strcmp(obj.ReconstructionCalibrationDropDown.ItemsData, calibration))
                    obj.ReconstructionCalibrationDropDown.Value = calibration;
                end
                obj.reconstruction_save_sfm_choice();
                obj.reconstruction_list_new_run_steps();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
            end
        end

        function go = reconstruction_offer_new_dataset_folder(obj)
            % Before a run on a recording that already has runs here: keep
            % them together (default), or start <stem>_01.matom
            % next to it. Nothing that exists is changed either way.
            % Returns false for Cancel.
            go = true;
            if ~obj.reconstruction_dataset_choice_ok(), return; end
            [root, recording, folder] = obj.reconstruction_dataset_names();
            n = rabbit_reconstruction_tab.dataset_run_count(root, folder);
            if n == 0, return; end
            next_stem = rabbit_reconstruction_tab.next_dataset_stem(root, recording);
            choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['%s.matom already holds %d run(s) of ' ...
                'this recording. Add this run to it, or start a new dataset folder, %s.matom, next to it? ' ...
                'The earlier runs are not changed either way. To see the runs of another folder, ' ...
                'use Dataset folder in step 1.'], folder, n, next_stem), 'Reconstruction run', ...
                'Options', {'Add to this folder', 'Start new folder', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            if strcmp(choice, 'Cancel')
                go = false;
                return;
            end
            if strcmp(choice, 'Start new folder')
                obj.reconstruction_bind_dataset(next_stem);
                go = ~isempty(obj.reconstruction_tab);
                if go
                    % Another dataset is bound now: its state and gate decide
                    [go, sync_err] = obj.reconstruction_sync_tool_paths();
                    if ~go
                        uialert(obj.host.opticalmappingUIFigure, sync_err, 'Reconstruction state');
                        return;
                    end
                    [go, gate_err] = obj.reconstruction_action_gate('run');
                    if ~go
                        obj.reconstruction_safe_refresh();
                        uialert(obj.host.opticalmappingUIFigure, gate_err, 'Reconstruction run');
                    end
                end
            end
        end

        % Helper: update the stage list and log viewer
        function reconstruction_update_stage_status(obj, run_id, stage, status) %#ok<INUSD>
            if isempty(obj.reconstruction_tab), return; end
            obj.reconstruction_render_status(run_id, stage);
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            drawnow;
        end

        % Helper: render the run status, stage list, results text and log viewer
        function tip = reconstruction_results_tooltip(~)
            %% The Results box's own tooltip (one text, put back on every redraw)
            tip = {'Status of the selected run: the verdict first, then what its checks found.'};
        end

        function reconstruction_render_status(obj, run_id, focus_stage)
            if isempty(obj.reconstruction_tab)
                return;
            end
            % the box's own tooltip again (a redo adds the folder to it)
            obj.ReconstructionResultsText.Tooltip = obj.reconstruction_results_tooltip();
            if nargin < 2 || isempty(run_id)
                run_id = obj.reconstruction_selected_run_id();
            end
            % The steps of the selected run; with no run, those of the
            % step 2 choice (10 when the sparse model is built)
            if isempty(run_id)
                stages = rabbit_reconstruction_tab.stage_order_for_source(obj.reconstruction_sparse_source(), ...
                    obj.ReconstructionCloudSourceDropDown.Value, obj.ReconstructionDenseDropDown.Value);
            else
                stages = obj.reconstruction_tab.stage_order_or_legacy(run_id);
            end
            n_stages = numel(stages);
            if isempty(run_id)
                items = cell(n_stages, 1);
                for k = 1:n_stages
                    items{k} = sprintf('Step %d of %d: %s [NOT STARTED]', k, n_stages, obj.reconstruction_stage_label(stages{k}, stages));
                end
                obj.ReconstructionStageList.Items = items;
                obj.ReconstructionStageList.ItemsData = stages;
                obj.reconstruction_stage_rows_refresh();
                obj.ReconstructionResultsText.Value = {'No reconstruction run selected.'};
                obj.ReconstructionLogViewer.Value = {'No log output recorded yet.'};
                obj.reconstruction_show_step('', '');
                obj.reconstruction_update_results_buttons('');
                return;
            end

            proj = obj.reconstruction_tab.reconstruction_stage_projection(run_id);
            items = cell(n_stages, 1);
            for k = 1:n_stages
                st_name = stages{k};
                st_status = 'NOT_STARTED';
                is_cur = false;
                is_res = false;
                for s_idx = 1:numel(proj.stages)
                    if strcmp(proj.stages(s_idx).name, st_name)
                        st_status = proj.stages(s_idx).status;
                        is_cur = proj.stages(s_idx).is_current;
                        is_res = proj.stages(s_idx).is_first_resumable;
                        break;
                    end
                end

                % While the run is going, its first unfinished step is the
                % one running, not one to resume
                running_now = is_res && strcmp(proj.run_status, 'RUNNING');
                if running_now
                    st_label = 'RUNNING';
                else
                    st_label = obj.reconstruction_status_label(st_status);
                end
                row_str = sprintf('Step %d of %d: %s [%s]', k, n_stages, ...
                    obj.reconstruction_stage_label(st_name, stages), st_label);
                if is_cur || running_now
                    row_str = ['> NOW ' row_str];
                elseif is_res
                    row_str = ['> RESUME HERE ' row_str];
                end
                items{k} = row_str;
            end
            obj.ReconstructionStageList.Items = items;
            obj.ReconstructionStageList.ItemsData = stages;

            chosen_stage = '';
            if nargin >= 3 && ~isempty(focus_stage) && any(strcmp(stages, focus_stage))
                chosen_stage = focus_stage;
            elseif ~isempty(proj.first_resumable_stage) && any(strcmp(stages, proj.first_resumable_stage))
                chosen_stage = proj.first_resumable_stage;
            elseif proj.is_running
                for k = 1:numel(proj.stages)
                    if proj.stages(k).is_current
                        chosen_stage = proj.stages(k).name;
                        break;
                    end
                end
            end
            if isempty(chosen_stage)
                % A run that has nothing left to do opens on the first step
                % that warned, so its warnings are in view
                warned = {proj.stages(strcmp({proj.stages.status}, 'WARNED')).name};
                k = find(ismember(stages, warned), 1);
                if ~isempty(k), chosen_stage = stages{k}; end
            end
            if isempty(chosen_stage)
                chosen_stage = stages{1};
            end
            obj.ReconstructionStageList.Value = chosen_stage;
            obj.reconstruction_stage_rows_refresh();
            obj.reconstruction_stage_rows_show_chosen();

            res = {};
            if strcmp(obj.unconfirmed_run_id, run_id)
                res = { ...
                    sprintf('Run %s - STATE NOT CONFIRMED.', run_id), ...
                    'Do not resume or start another run. Refresh after checking the manifest and tab-state files.'};
            elseif obj.reconstruction_cancel_pending(run_id)
                res = { ...
                    sprintf('Run %s status: CANCELLING.', run_id), ...
                    'Cancel requested. Waiting for the current step to stop.'};
            elseif strcmp(proj.run_status, 'COMPLETED')
                [is_clean, details] = obj.reconstruction_tab.reconstruction_completion_consistency(run_id);
                if isclean_or_true(is_clean)
                    % Verdict first, then a row per finding, every number
                    % from the run's record (rabbit_reconstruction_tab.
                    % results_box_lines); Details... gives the full text
                    % with the recording loaded now, so Results can say
                    % when the projection is of another
                    res = obj.reconstruction_tab.results_box_lines(run_id, true, obj.reconstruction_loaded_recording());
                    if isempty(res)
                        res = {sprintf('Run %s status: COMPLETED.', run_id), ...
                            'Its record could not be read for the checks: see Details...'};
                    end
                else
                    res = { ...
                        sprintf('Run %s status: COMPLETED - INCONSISTENT.', run_id), ...
                        'Some outputs or steps do not match a cleanly finished run:' ...
                    };
                    if isfield(details, 'discrepancies') && ~isempty(details.discrepancies)
                        for d_idx = 1:numel(details.discrepancies)
                            res{end+1} = sprintf('  - %s', details.discrepancies{d_idx}); %#ok<AGROW>
                        end
                    elseif isfield(details, 'first_discrepancy') && ~isempty(details.first_discrepancy)
                        res{end+1} = sprintf('  - %s', details.first_discrepancy);
                    end
                end
            elseif strcmp(proj.run_status, 'RUNNING')
                res = { ...
                    sprintf('Run %s status: RUNNING.', run_id), ...
                    sprintf('Running: %s.', obj.reconstruction_stage_label(chosen_stage, stages)) ...
                };
            elseif strcmp(proj.run_status, 'CANCELLED')
                res = { ...
                    sprintf('Run %s status: CANCELLED.', run_id), ...
                    ['It cannot be confirmed that every helper program has stopped: if the computer stays busy, ' ...
                    'check its running processes.'] ...
                };
                if ~isempty(proj.first_resumable_stage)
                    res{end+1} = sprintf('Resume starts at: %s.', obj.reconstruction_stage_label(proj.first_resumable_stage, stages));
                end
            elseif strcmp(proj.run_status, 'INTERRUPTED')
                res = { ...
                    sprintf('Run %s status: INTERRUPTED.', run_id), ...
                    ['The MATLAB session running it ended before it finished. ' ...
                    obj.reconstruction_tab.unconfirmed_stop_note()] ...
                };
                if ~isempty(proj.first_resumable_stage)
                    res{end+1} = sprintf('Resume starts at: %s.', obj.reconstruction_stage_label(proj.first_resumable_stage, stages));
                end
            elseif strcmp(proj.run_status, 'FAILED')
                res = { ...
                    sprintf('Run %s status: FAILED.', run_id) ...
                };
                if ~isempty(proj.first_resumable_stage)
                    res{end+1} = sprintf('Stopped at: %s. Resume starts there.', obj.reconstruction_stage_label(proj.first_resumable_stage, stages));
                end
            else
                res = {sprintf('Run %s status: %s.', run_id, proj.run_status)};
                if ~isempty(proj.first_resumable_stage)
                    res{end+1} = sprintf('Resume starts at: %s.', obj.reconstruction_stage_label(proj.first_resumable_stage, stages));
                end
            end

            if proj.out_of_order_count > 0
                res{end+1} = sprintf('Warning: %d step(s) finished out of order: %s', ...
                    proj.out_of_order_count, strjoin(cellfun(@(s) obj.reconstruction_stage_label(s, stages), ...
                    proj.out_of_order_stages, 'UniformOutput', false), ', '));
            end

            obj.ReconstructionResultsText.Value = res;
            obj.reconstruction_update_results_buttons(run_id);

            obj.reconstruction_show_step(run_id, chosen_stage);

            function tf = isclean_or_true(v)
                tf = ~isempty(v) && islogical(v) && v;
            end
        end
        function s = reconstruction_segmentation_choice(obj)
            % The segmentation settings a Run applies to the reconstruction
            % images: [] unless the segmentation window's checkbox was
            % ticked at Confirm area
            s = [];
            pd = obj.host.processed_data;
            if isfield(pd, 'reconstruction_segmentation') && isstruct(pd.reconstruction_segmentation) && ...
                    pd.reconstruction_segmentation.apply && isfield(pd, 'segmented') && pd.segmented
                s = pd.reconstruction_segmentation;
            end
        end

        function w = reconstruction_mask_words(~, recipe)
            % The recipe's masks in words, for the history
            if ~logical(recipe.masks.use)
                w = 'no masks';
            elseif strcmp(recipe.masks.source, 'folder')
                w = 'masks from a folder';
            else
                w = sprintf('tissue masks, %s', recipe.masks.source);
            end
        end

        function [frames, fps, video_note, go] = reconstruction_video_choice(obj, title)
            % Run's question about the OM video (as Reproject run asks):
            % with OM frames of the activation map's size loaded, "Map and
            % video" / "Map only" (default) / Cancel; without them, no
            % question and video_note says why (it is recorded with the
            % reprojection step). go = false on Cancel.
            frames = [];
            fps = 1;
            video_note = '';
            go = true;
            try
                stack = obj.host.processed_data.image_stack{obj.host.display.normalisation};
            catch
                stack = [];
            end
            if isempty(stack)
                video_note = 'no OM frames were loaded when the run started.';
                return;
            end
            if ndims(stack) ~= 3 || size(stack, 1) ~= size(obj.host.processed_data.activation_map, 1) || ...
                    size(stack, 2) ~= size(obj.host.processed_data.activation_map, 2)
                video_note = sprintf(['the OM frames (%s) were not the size of the activation map (%s) when the ' ...
                    'run started.'], mat2str(size(stack)), mat2str(size(obj.host.processed_data.activation_map)));
                return;
            end
            obj.host.focus_main_window();   % the question in front, not behind another window
            choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['The last step of the run projects the ' ...
                'activation map onto the mesh. Also project the OM video (%d frames)? This takes longer, and ' ...
                'with the video the map keeps only the pixels that have data in every frame.'], size(stack, 3)), ...
                title, 'Options', {'Map and video', 'Map only', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 3);
            if strcmp(choice, 'Cancel')
                go = false;
                return;
            end
            if strcmp(choice, 'Map and video')
                frames = stack;
                fps = obj.host.data.fps;
            else
                video_note = '"Map only" was chosen when the run started.';
            end
        end

        function reconstruction_rhythm_refresh(obj)
            %% Step 2's Pacing cycle shows the recording's rhythm marker (File > Recording rhythm)
            % One value in two places: the field holds the marker's cycle
            % in ms (blank when Not stated or no cycle was given). Marked
            % Sinus rhythm (no cycle), the field is blank and cannot be
            % typed in.
            r = rabbit_recording_rhythm.of(obj.host.data);
            fld = obj.ReconstructionPacingCycleField;
            if strcmp(r.state, 'sinus')
                fld.Value = '';
                fld.Editable = 'off';
                fld.Placeholder = 'sinus rhythm: no cycle';
                return;
            end
            fld.Editable = 'on';
            fld.Placeholder = 'not known';
            if strcmp(r.state, 'paced') && ~isempty(r.pacing_cycle_ms)
                fld.Value = rabbit_recording_rhythm.num(r.pacing_cycle_ms);
            else
                fld.Value = '';
            end
        end

        function s = reconstruction_loaded_recording(obj)
            %% The recording loaded in the app, for Results (name: its file name; rhythm: its marker)
            % The Results box warns when the
            % projection is of another recording, or of this one marked
            % with another rhythm (rabbit_reconstruction_tab.results_box_lines)
            % path: the file's full path, its stable
            % identity ('' when the app does not know its folder); the
            % display name alone can be relabelled
            s = struct('name', '', 'rhythm', [], 'path', '');
            try
                fi = obj.host.file_info;
                if isfield(fi, 'file') && ~isempty(fi.file)
                    s.name = char(fi.file);
                elseif isfield(fi, 'name') && ~isempty(fi.name)
                    s.name = char(fi.name);
                end
                if ~isempty(s.name) && isfield(fi, 'path') && ~isempty(fi.path)
                    [d, ~, ~] = fileparts(s.name);
                    if isempty(d), s.path = fullfile(char(fi.path), s.name); else, s.path = s.name; end
                end
                s.rhythm = rabbit_recording_rhythm.of(obj.host.data);
            catch
                % no app state to compare with: Results compares nothing
            end
        end

        function name = reconstruction_source_recording(obj)
            %% The loaded recording's file name, recorded with a projection (source_recording)
            % The Results box names the
            % recording projected; the file name only, no folder
            name = '';
            s = obj.reconstruction_loaded_recording();
            if ~isempty(s.name)
                parts = regexp(s.name, '[\\/]', 'split');
                name = parts{end};
            end
        end

        function p = reconstruction_source_recording_path(obj)
            %% The loaded recording's full path, recorded with a projection (source_recording_path)
            s = obj.reconstruction_loaded_recording();
            p = s.path;
        end

        function s = reconstruction_recording_rhythm(obj)
            %% The recording's rhythm marker as recorded with a projection (recording_rhythm)
            % With the near-simultaneous check of the activation map being
            % projected (the CV tab's basis), for the mismatch caution of
            % Results and Visualise (rabbit_recording_rhythm.mismatch).
            % of_app: with the beats Average beats found
            s = rabbit_recording_rhythm.record(rabbit_recording_rhythm.of_app(obj.host), rabbit_recording_rhythm.spread_of_app(obj.host));
        end

        function v = reconstruction_pacing_cycle_value(obj)
            %% The Pacing cycle field in ms, [] when blank (or not a positive number)
            % Marked Paced with a cycle, the marker's own value (the field
            % shows it rounded to 0.1 ms)
            v = [];
            try
                r = rabbit_recording_rhythm.of(obj.host.data);
                if strcmp(r.state, 'paced') && ~isempty(r.pacing_cycle_ms)
                    v = r.pacing_cycle_ms;
                    return;
                end
            catch
                % a host without a rhythm marker (test doubles)
            end
            txt = strtrim(char(obj.ReconstructionPacingCycleField.Value));
            if isempty(txt), return; end
            x = str2double(txt);
            if isfinite(x) && x > 0, v = x; end
        end

        function reconstruction_pacing_cycle_changed(obj, ev)
            %% Check the Pacing cycle field: blank, or a positive number of ms
            % Anything else is refused with a message and the field goes
            % back to what it held
            txt = strtrim(char(obj.ReconstructionPacingCycleField.Value));
            x = str2double(txt);
            if isempty(txt) || (isfinite(x) && x > 0 && isreal(x))
                obj.ReconstructionPacingCycleField.Value = txt;
                % The same value as File > Recording rhythm: the marker
                % follows (a number: Paced with that cycle)
                try
                    rabbit_recording_rhythm.from_step2(obj.host, txt);
                catch
                    % a host without a rhythm marker (test doubles)
                end
                return;
            end
            old = '';
            if isstruct(ev) || isobject(ev)
                try
                    old = char(ev.PreviousValue);
                catch
                end
            end
            obj.ReconstructionPacingCycleField.Value = old;
            uialert(obj.host.opticalmappingUIFigure, sprintf(['"%s" is not a pacing cycle. Type the cycle length ' ...
                'in ms as a positive number (2 Hz = 500 ms), or leave the field blank when it is not known.'], txt), ...
                'Pacing cycle', 'Icon', 'warning');
        end

        function reconstruction_om_pose_frame_changed(obj)
            % "OM pose frame" takes Automatic or a whole frame number; any
            % other text goes back to Automatic with a note
            v = strtrim(char(obj.ReconstructionOmPoseFrameDropDown.Value));
            n = str2double(v);
            if strcmpi(v, 'Automatic')
                return;
            end
            if isfinite(n) && n > 0 && n == round(n)
                % A frame the sparse model never uses can never be the pose
                % frame: say so now, not at the last step of a run. Only when the frames are known: a built
                % sparse model with its images and ROI file chosen.
                try
                    [recipe, ~] = obj.reconstruction_sfm_recipe();
                    imgs = obj.ReconstructionImagesField.Value;
                    roi = obj.ReconstructionRoiField.Value;
                    if ~isempty(recipe) && strcmp(obj.reconstruction_sparse_source(), 'built') && ...
                            isfolder(imgs) && exist(roi, 'file') == 2
                        [r_ok, ~, rr] = rabbit_sfm_build.resolve(recipe, struct('images_dir', imgs, 'roi_json', roi));
                        fr = rr.resolved.frames;
                        if r_ok && ~ismember(n, fr)
                            obj.ReconstructionOmPoseFrameDropDown.Value = 'Automatic';
                            if numel(fr) > 6
                                list = sprintf('%d, %d, %d, ... %d', fr(1), fr(2), fr(3), fr(end));
                            else
                                list = strjoin(arrayfun(@num2str, fr, 'UniformOutput', false), ', ');
                            end
                            uialert(obj.host.opticalmappingUIFigure, sprintf(['Frame %d is not one of the frames the ' ...
                                'sparse model uses (%s), so its cameras would never be known. It was set back to ' ...
                                'Automatic; type one of those frames, or keep Automatic.'], n, list), 'OM pose frame');
                        end
                    end
                catch
                    % the frames cannot be listed yet: the run checks the frame
                end
                return;
            end
            obj.ReconstructionOmPoseFrameDropDown.Value = 'Automatic';
            uialert(obj.host.opticalmappingUIFigure, ['OM pose frame takes Automatic or a frame number of the ' ...
                'reconstruction recording (e.g. 1). It was set back to Automatic.'], 'OM pose frame');
        end

        function lines = reconstruction_projection_lines(obj, m, row_views, run_dir)
            % The projection check of a run in plain words (which frame's
            % cameras were used, how well the OM heart outline matched
            % them, how much of the heart the mesh covers), from the run
            % manifest; {} when the run has none. One labelled line each:
            % Camera frame, Outline match, Mesh coverage,
            % Pose uncertainty, Next step; values View1 to View4: the record
            % lists them per ROI row (the images named _view<k>,
            % rabbit_rhythm_reproject frame_check), and row_views (the
            % tab's run_row_views, from the regions file) names each row's
            % view ([1 2 3 4] when not given). A record without
            % those fields keeps its summary.
            % run_dir (optional): the run, for the pose as distances on the
            % heart
            if nargin < 3 || numel(row_views) ~= 4, row_views = 1:4; end
            if nargin < 4, run_dir = ''; end
            lines = {};
            try
                fc = m.result.reprojection.frame_check;
            catch
                return;
            end
            if ~isstruct(fc) || ~isfield(fc, 'summary') || isempty(fc.summary), return; end
            smry = char(fc.summary);
            if ~all(isfield(fc, {'frame', 'pose_iou', 'om_covered'})) || isempty(fc.pose_iou) || isempty(fc.om_covered)
                lines = {sprintf('Projection check (%s): %s', fc.verdict, smry)};
                return;
            end
            L = rabbit_rhythm_reproject.frame_check_limits();
            deg = char(176);
            % ROI row values put in view order (View1 first)
            in_views = @(x) obj.reconstruction_tab.by_view_order(x, row_views);
            by_view = @(x, fmt) strjoin(arrayfun(@(k) sprintf(['View%d ' fmt], k, x(k)), 1:numel(x), ...
                'UniformOutput', false), ', ');
            % Outline matches: 3 decimals within 0.01 of a limit, as Results
            % (near_limit_formats)
            by_view_iou = @(x) strjoin(cellfun(@(k, f) sprintf(['View%d ' f], k, x(k)), num2cell(1:numel(x)), ...
                obj.reconstruction_tab.near_limit_formats(x, L), 'UniformOutput', false), ', ');
            lines = {sprintf('Projection check (%s):', fc.verdict)};
            % Camera frame: as the check chose it; the margin and the
            % number of frames compared are in its summary
            frame = double(fc.frame(1));
            how = 'chosen automatically';
            if isfield(fc, 'chosen_by') && strcmp(char(fc.chosen_by), 'manual')
                how = 'set by hand (OM pose frame)';
            elseif isfield(fc, 'best_score_frame') && ~isempty(fc.best_score_frame) && ...
                    double(fc.best_score_frame(1)) ~= frame
                margin = regexp(smry, 'within ([\d.]+) of the best', 'tokens', 'once');
                if isempty(margin), margin = {sprintf('%.2f', L.ambiguity_margin)}; end
                how = sprintf('the earliest frame within %s outline-match score of the best frame (frame %d)', margin{1}, ...
                    double(fc.best_score_frame(1)));
            end
            n_reg = regexp(smry, '\((\d+) frames had all four views registered\)', 'tokens', 'once');
            reg = '';
            if ~isempty(n_reg), reg = sprintf('; %s frames had all four views registered', n_reg{1}); end
            lines{end + 1} = sprintf('  Camera frame: %d, %s%s.', frame, how, reg);
            lines{end + 1} = sprintf('  Camera-image outline match (1 = identical): %s (warn < %.2f, stop < %.2f).', ...
                by_view_iou(in_views(fc.pose_iou)), L.pose_iou_warn, L.pose_iou_fail);
            % The OM outline against the mesh silhouette
            if isfield(fc, 'mesh_iou') && isnumeric(fc.mesh_iou) && numel(fc.mesh_iou) == numel(fc.pose_iou)
                lines{end + 1} = sprintf('  Mesh outline match (OM outline against the mesh; 1 = identical): %s (warn < %.2f, stop < %.2f).', ...
                    by_view_iou(in_views(fc.mesh_iou)), L.pose_iou_warn, L.pose_iou_fail);
            end
            lines{end + 1} = sprintf('  Mesh coverage (share of the heart in each OM view): %s (warn < %.0f %%).', ...
                by_view(100 * in_views(fc.om_covered), '%.0f %%'), 100 * L.covered_warn);
            far = [];
            turn = [];
            if isfield(fc, 'ambiguous_frames'), far = double(fc.ambiguous_frames(:)'); end
            if isfield(fc, 'ambiguous_turn_deg'), turn = double(fc.ambiguous_turn_deg(:)'); end
            if ~isempty(far) && numel(turn) == numel(far)
                parts = arrayfun(@(f, a) sprintf('%d (%.0f%s)', f, a, deg), far, turn, 'UniformOutput', false);
                lines{end + 1} = sprintf(['  Pose uncertainty: frames %s match as well, with the heart turned by up ' ...
                    'to %.0f%s; the OM pose is known only to within about %.0f%s.'], strjoin(parts, ', '), ...
                    max(turn), deg, max(turn), deg);
                % Positions on the heart, as the Results pose row
                % (pose_position_words, a run in mm only)
                mm_txt = '';
                try
                    if ~isempty(run_dir)
                        [~, mm_txt] = obj.reconstruction_tab.pose_position_words(run_dir, m, max(turn));
                    end
                catch
                    mm_txt = '';
                end
                if ~isempty(mm_txt)
                    lines{end} = sprintf('%s Positions %s.', lines{end}, mm_txt);
                end
                % The Results text, so Details says the same
                nxt = 'Next: if the lab notes give the frame at which the OM was recorded, type it in "OM pose frame" (Step 2) and press Redo projection.';
                try
                    nxt = obj.reconstruction_tab.pose_next_words(run_dir, m, fc);
                catch
                    % without the run folder: the first sentence only
                end
                lines{end + 1} = ['  ' regexprep(nxt, '^Next: ', 'Next step: ')];
            else
                lines{end + 1} = '  Pose uncertainty: no other frame matches as well.';
            end
            % What the summary adds beyond these (the mesh outline only,
            % frames not compared)
            extra = regexp(smry, '(The camera images had no tissue outline[^.]*\.[^.]*\.|Frames [\d, ]+ were not compared[^.]*\.)', ...
                'match');
            for k = 1:numel(extra)
                lines{end + 1} = ['  Note: ' extra{k}]; %#ok<AGROW>
            end
        end
        function reconstruction_offer_attempt_cleanup(obj, run_id)
            % A retry of a sparse step or the undistortion keeps the
            % earlier attempt beside it (<stage>.attempt_<time>), on the
            % dataset drive. When a run or resume ends, list them with
            % their sizes and offer to remove them; nothing is removed
            % unless the user chooses Remove (the default is Keep).
            if isempty(obj.reconstruction_tab) || isempty(run_id), return; end
            try
                A = obj.reconstruction_tab.attempt_folders(run_id);
            catch
                return;
            end
            if isempty(A), return; end
            items = arrayfun(@(a) sprintf('%s (%s)', a.name, obj.reconstruction_tab.size_text(a.bytes)), A, ...
                'UniformOutput', false);
            choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['Run %s keeps %d earlier attempt(s) of its ' ...
                'steps, %s in all, next to the dataset:\n%s\nThe run''s results do not need them. Remove them?'], ...
                run_id, numel(A), obj.reconstruction_tab.size_text(sum([A.bytes])), strjoin(items, '\n')), ...
                'Earlier attempts', 'Options', {'Remove', 'Keep'}, 'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(choice, 'Remove'), return; end
            errs = {};
            for k = 1:numel(A)
                [ok, err] = obj.reconstruction_tab.remove_attempt_folder(run_id, A(k).name);
                if ~ok, errs{end+1} = err; end %#ok<AGROW>
            end
            if ~isempty(errs)
                uialert(obj.host.opticalmappingUIFigure, strjoin(errs, newline), 'Earlier attempts');
            end
        end
        function run_id = reconstruction_selected_run_id(obj)
            value = obj.ReconstructionRunList.Value;
            if iscell(value)
                if isempty(value)
                    run_id = '';
                else
                    run_id = value{1};
                end
            elseif isstring(value)
                if isempty(value)
                    run_id = '';
                else
                    run_id = char(value(1));
                end
            else
                run_id = value;
            end
            % The list displays "run_id [status]"; the backend needs only
            % the immutable run ID.
            if isstring(run_id)
                run_id = char(run_id);
            end
            if ischar(run_id)
                marker = strfind(run_id, ' [');
                if ~isempty(marker)
                    run_id = run_id(1:marker(1)-1);
                end
            end
            if ~obj.steps_run_id_valid(run_id)
                run_id = '';
            else
                runs = obj.reconstruction_validated_runs();
                if isempty(runs) || ~any(strcmp({runs.id}, run_id))
                    run_id = '';
                end
            end
        end

        % Helper: update the run list from validated tab state
        function reconstruction_update_run_list(obj)
            if isempty(obj.reconstruction_tab)
                obj.ReconstructionRunList.Items = {};
                obj.ReconstructionRunList.Value = {};
                obj.ReconstructionRunListEmptyLabel.Visible = 'on';
                return;
            end
            % Validate before rendering: malformed entries are absent, not
            % selectable placeholders. A heterogeneous JSON array is allowed
            % to contain malformed records without hiding valid RUNNING ones.
            runs = obj.reconstruction_validated_runs();
            if isempty(runs)
                obj.ReconstructionRunList.Items = {};
                obj.ReconstructionRunList.Value = {};
                obj.ReconstructionRunListEmptyLabel.Visible = 'on';
                return;
            end
            items = cell(numel(runs), 1);
            for k = 1:numel(runs)
                % The durable status is the authority.
                [eff, is_dur] = obj.reconstruction_effective_status(runs(k).id);
                if isempty(eff)
                    % A manifest that EXISTS but is unreadable must not
                    % render as the
                    % tab-state status (the list would lie about durable state).
                    if is_dur
                        eff = 'UNREADABLE';
                    else
                        eff = runs(k).status;
                    end
                end
                if strcmp(eff, 'COMPLETED') && ~obj.reconstruction_run_consistent(runs(k).id)
                    eff = 'COMPLETED - INCONSISTENT';
                end
                lab = obj.reconstruction_status_label(eff);
                % A finished run under the defect rule says so in the
                % list too
                if strcmp(eff, 'COMPLETED') && obj.reconstruction_tab.run_not_for_analysis(runs(k).id)
                    lab = sprintf('COMPLETED %s NOT FOR ANALYSIS', char(183));
                end
                items{k} = sprintf('%s [%s]', runs(k).id, lab);
            end
            % Keep the selected run selected when its line changes (its
            % status in brackets): a list box whose value is no longer one
            % of its items falls back to the first item, so after a second
            % run finished the list (and Visualise, Resume, Reproject)
            % would go back to the first run
            try
                prev_id = obj.reconstruction_selected_run_id();
            catch
                prev_id = '';
            end
            obj.ReconstructionRunList.Items = items;
            if ~isempty(prev_id)
                k_sel = find(strncmp(items, [prev_id ' ['], numel(prev_id) + 2), 1);
                if ~isempty(k_sel)
                    obj.ReconstructionRunList.Value = items{k_sel};
                end
            end
            obj.ReconstructionRunListEmptyLabel.Visible = 'off';
            obj.ReconstructionRunList.Visible = 'on';
            obj.reconstruction_edit_refresh();
        end

        % ---- Step 2: build the sparse model ----

        function source = reconstruction_sparse_source(obj)
            % 'built' when step 2 builds the sparse model, else 'supplied'
            source = 'supplied';
            try
                if strcmp(obj.ReconstructionSparseSourceDropDown.Value, 'built')
                    source = 'built';
                end
            catch
                % control missing (e.g. an App Designer re-save dropped it)
            end
        end

        function reconstruction_show_sparse_source(obj)
            % Row 2 of step 2: recipe and Details... when building, the
            % sparse model folder and Browse... otherwise
            built = strcmp(obj.reconstruction_sparse_source(), 'built');
            obj.ReconstructionSfmRecipeDropDown.Visible = obj.steps_pick(built);
            obj.ReconstructionSfmDetailsButton.Visible = obj.steps_pick(built);
            obj.ReconstructionCalibrationLabel.Visible = obj.steps_pick(built);
            obj.ReconstructionCalibrationDropDown.Visible = obj.steps_pick(built);
            obj.ReconstructionCalibrateButton.Visible = obj.steps_pick(built);
            obj.ReconstructionPycamsetGuiButton.Visible = obj.steps_pick(built);
            obj.ReconstructionCamsetField.Visible = obj.steps_pick(built);
            obj.ReconstructionCamsetButton.Visible = obj.steps_pick(built);
            obj.ReconstructionSparseField.Visible = obj.steps_pick(~built);
            obj.ReconstructionSparseButton.Visible = obj.steps_pick(~built);
            % The dense clouds chosen for this source (else its default)
            obj.ReconstructionDenseDropDown.Value = obj.reconstruction_dense_by_source.(obj.reconstruction_sparse_source());
            obj.reconstruction_dense_sync();
            if built
                obj.ReconstructionSparseLabel.Text = 'Sparse model: built from the images';
            else
                obj.ReconstructionSparseLabel.Text = 'Sparse model';
            end
        end

        function reconstruction_list_new_run_steps(obj)
            % With no run selected, list the steps a new run would have
            % (the sparse model steps when it is built; the APDe-MVS steps
            % with "APDe-MVS + COLMAP")
            if ~isempty(obj.reconstruction_tab) && ~isempty(obj.reconstruction_selected_run_id())
                return;
            end
            stages = rabbit_reconstruction_tab.stage_order_for_source(obj.reconstruction_sparse_source(), ...
                obj.ReconstructionCloudSourceDropDown.Value, obj.ReconstructionDenseDropDown.Value);
            items = cell(numel(stages), 1);
            for k = 1:numel(stages)
                items{k} = sprintf('Step %d of %d: %s [NOT STARTED]', k, numel(stages), ...
                    obj.reconstruction_stage_label(stages{k}, stages));
            end
            obj.ReconstructionStageList.Items = items;
            obj.ReconstructionStageList.ItemsData = stages;
            obj.reconstruction_stage_rows_refresh();
        end

        function reconstruction_stage_rows_refresh(obj)
            % Show the step list as one-line tiles: a word chip (OK, WARN,
            % FAIL, RUNNING, NOT RUN) tinted by the step's state, and a
            % button with the step's number and name. Called whenever the
            % list or its selection changes. The tiles are made again only
            % when the number of steps changes (8 or 10).
            row_height = obj.reconstruction_stage_row_height();
            items = obj.ReconstructionStageList.Items;
            stages = obj.ReconstructionStageList.ItemsData;
            n = numel(items);
            if numel(obj.StageRowButtons) ~= n
                cellfun(@delete, obj.StageRowButtons);
                cellfun(@delete, obj.StageRowChips);
                obj.StageRowButtons = cell(1, n);
                obj.StageRowChips = cell(1, n);
                obj.StageRowsGrid.RowHeight = repmat({row_height}, 1, n);
                for k = 1:n
                    c = uilabel(obj.StageRowsGrid);
                    c.HorizontalAlignment = 'center';
                    c.FontWeight = 'bold';
                    c.Layout.Row = k;
                    c.Layout.Column = 1;
                    obj.StageRowChips{k} = c;
                    b = uibutton(obj.StageRowsGrid, 'push');
                    b.HorizontalAlignment = 'left';
                    b.Layout.Row = k;
                    b.Layout.Column = 2;
                    b.Tooltip = {'Select a step to see its warnings and log.'};
                    b.ButtonPushedFcn = @(src, ev) reconstruction_stage_row_pressed(obj, k);
                    obj.StageRowButtons{k} = b;
                end
            end
            obj.GridLayoutR2.RowHeight{2} = n * (row_height + obj.StageRowsGrid.RowSpacing) + 4;
            chosen = obj.ReconstructionStageList.Value;
            for k = 1:n
                [txt, chip] = obj.reconstruction_stage_row_text(items{k});
                b = obj.StageRowButtons{k};
                b.Text = txt;
                b.Tooltip = {['Step ' txt]; 'Select a step to see its warnings and log.'};
                c = obj.StageRowChips{k};
                c.Text = chip;
                c.BackgroundColor = obj.reconstruction_chip_colour(chip);
                is_chosen = strcmp(stages{k}, chosen);
                b.FontWeight = obj.steps_ternary(is_chosen, 'bold', 'normal');
                if is_chosen
                    b.BackgroundColor = [0.80 0.88 1.00];
                else
                    b.BackgroundColor = [0.96 0.96 0.96];
                end
            end
        end

        function c = reconstruction_chip_colour(obj, chip) %#ok<INUSL>
            % The tint of a step's word chip
            switch chip
                case 'OK',      c = [0.78 0.91 0.78];
                case 'WARN',    c = [1.00 0.85 0.55];
                case 'FAIL',    c = [1.00 0.72 0.72];
                case 'RUNNING', c = [0.74 0.84 1.00];
                otherwise,      c = [0.88 0.88 0.88];
            end
        end

        function reconstruction_stage_rows_show_chosen(obj)
            % Scroll the Steps list so the selected step is in view.
            % The vertical position is 1 at the top and goes negative
            % further down the column.
            stages = obj.ReconstructionStageList.ItemsData;
            k = find(strcmp(stages, obj.ReconstructionStageList.Value), 1);
            if isempty(k), return; end
            step = obj.reconstruction_stage_row_height() + obj.StageRowsGrid.RowSpacing;
            drawnow nocallbacks;   % rows just made must be laid out first
            scroll(obj.StageRowsGrid, 1, 1 - (k - 1) * step);
        end

        function h = reconstruction_stage_row_height(obj) %#ok<MANU>
            % Height in pixels of one step tile: one line of text
            h = 26;
        end

        function [txt, chip] = reconstruction_stage_row_text(obj, item)
            % 'Step 2 of 8: Name [STATE]' as a tile: '2  Name' and the
            % chip word of the state. The step being run or to resume
            % next says so after its name.
            state = '';
            s = regexp(item, '^(.*) \[([^\[\]]*)\]$', 'tokens', 'once');
            if ~isempty(s)
                item = s{1};
                state = s{2};
            end
            mark = '';
            if startsWith(item, '> NOW ')
                mark = ' (now)';
            elseif startsWith(item, '> RESUME HERE ')
                mark = ' (resume here)';
            end
            t = regexp(item, 'Step (\d+) of \d+: (.*)$', 'tokens', 'once');
            if isempty(t)
                txt = item;
            else
                txt = sprintf('%s  %s%s', t{1}, t{2}, mark);
            end
            switch state
                case {'PASSED', 'PASSED WITH WARNINGS'}
                    chip = obj.steps_ternary(strcmp(state, 'PASSED'), 'OK', 'WARN');
                case 'FAILED',  chip = 'FAIL';
                case 'RUNNING', chip = 'RUNNING';
                otherwise,      chip = 'NOT RUN';
            end
        end

        function reconstruction_show_log(obj)
            % Show log ticked: the log, with its header, under the warnings;
            % unticked: the warnings take its place
            show = obj.ReconstructionShowLogCheckBox.Value;
            obj.ReconstructionLogLabel.Parent.Visible = obj.steps_pick(show);
            obj.ReconstructionLogViewer.Visible = obj.steps_pick(show);
            if show
                obj.GridLayoutR2.RowHeight(3:5) = {obj.reconstruction_warnings_height(), 24, '1x'};
            else
                obj.GridLayoutR2.RowHeight(3:5) = {'1x', 0, 0};
            end
        end

        function h = reconstruction_warnings_height(obj)
            % Height (pixels) the step warnings take with the log shown:
            % every line, wrapped at the box's width, at least 96 and at
            % most 240 (the log keeps the rest)
            lines = cellstr(obj.StepWarningsText.Value);
            w = obj.StepWarningsText.Position(3);
            if w < 50, w = 400; end
            chars = max(20, floor((w - 24) / 7));   % about 7 pixels a character
            n = sum(cellfun(@(s) max(1, ceil(numel(s) / chars)), lines));
            h = min(240, max(96, 16 * n + 12));
        end

        function stage = reconstruction_selected_stage(obj)
            % The step selected in the Steps list ('' when none)
            stage = obj.ReconstructionStageList.Value;
            if iscell(stage)
                if isempty(stage), stage = ''; else, stage = stage{1}; end
            end
            stage = char(stage);
        end

        function reconstruction_show_step(obj, run_id, stage)
            % The selected step's warnings and log, and its earlier attempts
            obj.reconstruction_show_step_warnings(run_id, stage);
            obj.reconstruction_update_attempts(run_id, stage);
            obj.reconstruction_show_step_log();
        end

        function reconstruction_show_step_warnings(obj, run_id, stage)
            % One line per warning of the selected step: the check's plain
            % name, the measured value and its limit (the same rows as the
            % Results box, read from the run's record)
            if isempty(run_id) || isempty(stage) || isempty(obj.reconstruction_tab)
                obj.StepWarningsText.Value = {'Select a run to see the warnings of its steps.'};
                return;
            end
            stages = obj.ReconstructionStageList.ItemsData;
            k = find(strcmp(stages, stage), 1);
            [txt, chip] = obj.reconstruction_stage_row_text(obj.ReconstructionStageList.Items{k});
            head = sprintf('Step %s: %s', txt, chip);
            try
                lines = obj.reconstruction_tab.step_warning_lines(run_id, stage);
            catch
                lines = {};
            end
            if isempty(lines)
                if strcmp(chip, 'WARN')
                    lines = {'Its warnings could not be read: see the log.'};
                else
                    lines = {'No warnings.'};
                end
            end
            obj.StepWarningsText.Value = [{head}, lines(:)'];
            if obj.ReconstructionShowLogCheckBox.Value
                obj.reconstruction_show_log();   % its height follows its lines
            end
        end

        function reconstruction_update_attempts(obj, run_id, stage)
            % Attempt: "latest", and each earlier attempt of the step that a
            % retry kept beside it (<stage>.attempt_<time>)
            items = {'latest'};
            data = {''};
            if ~isempty(run_id) && ~isempty(stage) && ~isempty(obj.reconstruction_tab)
                try
                    A = obj.reconstruction_tab.attempt_folders(run_id);
                catch
                    A = struct('name', {}, 'path', {});
                end
                for k = numel(A):-1:1
                    % stages/<step>.attempt_<time>, or a folder inside the step's own
                    if ~startsWith(A(k).name, ['stages/' stage '.attempt_']) && ...
                            ~startsWith(A(k).name, ['stages/' stage '/'])
                        continue;
                    end
                    t = regexp(A(k).name, '\.attempt_(\d{8}T\d{6})', 'tokens', 'once');
                    if isempty(t), continue; end
                    items{end + 1} = ['earlier, ' t{1}]; %#ok<AGROW>
                    data{end + 1} = A(k).path; %#ok<AGROW>
                end
            end
            obj.ReconstructionAttemptDropDown.Items = items;
            obj.ReconstructionAttemptDropDown.ItemsData = data;
            obj.ReconstructionAttemptDropDown.Value = '';
            obj.ReconstructionAttemptDropDown.Enable = obj.steps_pick(numel(items) > 1);
        end

        function reconstruction_show_step_log(obj)
            % The log of the selected step: the latest attempt from its
            % record (outputs counted, not listed), or an earlier attempt's
            % own log files
            run_id = obj.reconstruction_selected_run_id();
            stage = obj.reconstruction_selected_stage();
            if isempty(run_id) || isempty(stage) || isempty(obj.reconstruction_tab)
                obj.ReconstructionLogViewer.Value = {'No log output recorded yet.'};
                return;
            end
            attempt = obj.ReconstructionAttemptDropDown.Value;
            if ~isempty(attempt)
                lines = {sprintf('Earlier attempt, kept in %s', attempt)};
                logs = dir(fullfile(attempt, '*.log'));
                for k = 1:numel(logs)
                    lines{end + 1} = sprintf('-- %s (last 200 lines) --', logs(k).name); %#ok<AGROW>
                    try
                        t = strsplit(strrep(fileread(fullfile(attempt, logs(k).name)), sprintf('\r'), ''), newline);
                        lines = [lines, t(max(1, end - 199):end)]; %#ok<AGROW>
                    catch
                        lines{end + 1} = 'The log could not be read.'; %#ok<AGROW>
                    end
                end
                if isempty(logs), lines{end + 1} = 'No log file in that folder.'; end
                obj.ReconstructionLogViewer.Value = lines;
                return;
            end
            act = obj.reconstruction_tab.stage_activity(run_id, stage, 200);
            if isempty(act)
                obj.ReconstructionLogViewer.Value = {'No log output recorded yet.'};
            elseif isstruct(act) && isfield(act, 'lines')
                obj.ReconstructionLogViewer.Value = obj.reconstruction_mark_earlier_attempts( ...
                    obj.reconstruction_count_outputs(act.lines), stage);
            elseif ischar(act) || isstring(act)
                obj.ReconstructionLogViewer.Value = cellstr(strsplit(strrep(char(act), sprintf('\r'), ''), sprintf('\n')));
            else
                obj.ReconstructionLogViewer.Value = {'No log output recorded yet.'};
            end
        end

        function lines = reconstruction_mark_earlier_attempts(obj, lines, stage) %#ok<INUSL>
            % The step's log keeps every attempt; each attempt ends with
            % "stage <step> PASSED / WARNED / FAILED / CANCELLED". In the
            % log tail, the lines of an attempt before the latest get
            % "earlier attempt (<its result>): " in front, so an old FAILED
            % line is not read as the step's result
            k0 = find(startsWith(lines, '-- Existing log tail'), 1);
            if isempty(k0), return; end
            pat = ['\] stage ' regexptranslate('escape', stage) ' (PASSED|WARNED|FAILED|CANCELLED)\>'];
            ends = [];
            res = {};
            for k = k0 + 1:numel(lines)
                t = regexp(lines{k}, pat, 'tokens', 'once');
                if ~isempty(t)
                    ends(end + 1) = k; %#ok<AGROW>
                    res{end + 1} = lower(t{1}); %#ok<AGROW>
                end
            end
            % With the last line the latest result, every attempt before
            % it is earlier; while the step runs again, all ended ones are
            last = numel(lines);
            while last > k0 && isempty(strtrim(lines{last})), last = last - 1; end
            if ~isempty(ends) && ends(end) == last
                ends = ends(1:end - 1);
                res = res(1:end - 1);
            end
            from = k0 + 1;
            for a = 1:numel(ends)
                for k = from:ends(a)
                    if ~isempty(strtrim(lines{k}))
                        lines{k} = sprintf('earlier attempt (%s): %s', res{a}, lines{k});
                    end
                end
                from = ends(a) + 1;
            end
        end

        function lines = reconstruction_count_outputs(obj, lines) %#ok<INUSL>
            % The step's outputs as "Outputs: N files" instead of a list of
            % every file (a sparse step writes hundreds); Open folder shows them
            k = find(strcmp(lines, 'Outputs:'), 1);
            if isempty(k), return; end
            j = k + 1;
            while j <= numel(lines) && startsWith(lines{j}, '  - ')
                j = j + 1;
            end
            n = j - k - 1;
            lines = [lines(1:k - 1), {sprintf('Outputs: %d %s', n, obj.steps_ternary(n == 1, 'file', 'files'))}, ...
                lines(j:end)];
        end

        function reconstruction_open_step_folder(obj)
            % Open folder: the selected attempt's folder, else the step's
            % folder in the run, else the run folder
            run_dir = obj.reconstruction_selected_run_dir();
            if isempty(run_dir)
                uialert(obj.host.opticalmappingUIFigure, 'Select a run first.', 'Open folder');
                return;
            end
            folder = obj.ReconstructionAttemptDropDown.Value;
            if isempty(folder) || ~isfolder(folder)
                folder = fullfile(run_dir, 'stages', obj.reconstruction_selected_stage());
            end
            if ~isfolder(folder)
                folder = run_dir;
            end
            rabbit_reconstruction_ui.open_folder(folder);
        end

        function reconstruction_stage_row_pressed(obj, k)
            % A step row was pressed: select it, as the list box would
            stages = obj.ReconstructionStageList.ItemsData;
            if k > numel(stages), return; end
            obj.ReconstructionStageList.Value = stages{k};
            obj.ReconstructionStageListValueChanged();
            obj.reconstruction_stage_rows_refresh();
        end

        function reconstruction_dense_sync(obj)
            % "Cloud used to build the mesh" is a choice only with APDe-MVS +
            % COLMAP; with COLMAP alone it shows the COLMAP cloud, disabled.
            % The tooltip says it is for the next run: the selected run's
            % mesh input is in its Results
            dd = obj.ReconstructionCloudSourceDropDown;
            nxt = 'For the next run; the mesh input of the selected run is shown in its Results.';
            if strcmp(obj.ReconstructionDenseDropDown.Value, 'both')
                dd.Enable = 'on';
                dd.Tooltip = {nxt; 'COLMAP: the mesh is built from the COLMAP fused cloud (default)'; ...
                    'APDe-MVS: the mesh is built from the APDe-MVS cloud; the COLMAP cloud still tells the mesh check which cameras see each point'};
            else
                dd.Value = 'fused';
                dd.Enable = 'off';
                dd.Tooltip = {nxt; 'Only the COLMAP cloud is computed, so the mesh is built from it. Set "Clouds to compute" to "APDe-MVS + COLMAP" to choose here.'};
            end
        end

        function reconstruction_dense_changed(obj)
            % The dense clouds of a new run: remembered for the sparse model
            % source; the mesh's cloud, the step list and the gates follow
            obj.reconstruction_dense_by_source.(obj.reconstruction_sparse_source()) = obj.ReconstructionDenseDropDown.Value;
            obj.reconstruction_dense_sync();
            obj.reconstruction_list_new_run_steps();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        function reconstruction_cloud_source_changed(obj)
            % The cloud the mesh is made from ("Cloud used to build the mesh"): the step list, the
            % journey and the gates are refreshed. Which steps a new run
            % has follows the dense cloud (reconstruction_dense_changed)
            obj.reconstruction_list_new_run_steps();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        function reconstruction_sparse_source_changed(obj)
            % Build or supply the sparse model: show the matching
            % controls, remember the choice, and refresh the step list
            obj.reconstruction_show_sparse_source();
            obj.reconstruction_save_sfm_choice();
            obj.reconstruction_list_new_run_steps();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        function ReconstructionSfmRecipeDropDownValueChanged(obj)
            % "Custom recipe file...": pick a recipe JSON and check it;
            % back to the default when nothing usable was chosen
            if strcmp(obj.ReconstructionSfmRecipeDropDown.Value, 'custom')
                [f, pth] = uigetfile('*.json', 'Sparse model recipe (JSON)');
                if isequal(f, 0)
                    obj.ReconstructionSfmRecipeDropDown.Value = 'rabbit_4view_v1';
                    obj.reconstruction_sfm_recipe_file = '';
                else
                    file = fullfile(pth, f);
                    [~, err] = rabbit_sfm_build.from_json_file(file);
                    if ~isempty(err)
                        uialert(obj.host.opticalmappingUIFigure, err, 'Sparse model recipe');
                        obj.ReconstructionSfmRecipeDropDown.Value = 'rabbit_4view_v1';
                        obj.reconstruction_sfm_recipe_file = '';
                    else
                        obj.reconstruction_sfm_recipe_file = file;
                    end
                end
            else
                obj.reconstruction_sfm_recipe_file = '';
            end
            obj.reconstruction_save_sfm_choice();
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
        end

        function [recipe, err] = reconstruction_sfm_recipe(obj)
            % The recipe step 2 would use: the custom file, or the default
            err = '';
            if strcmp(obj.ReconstructionSfmRecipeDropDown.Value, 'custom') && ...
                    ~isempty(obj.reconstruction_sfm_recipe_file)
                [recipe, err] = rabbit_sfm_build.from_json_file(obj.reconstruction_sfm_recipe_file);
                if ~isempty(err), recipe = []; end
            else
                recipe = rabbit_sfm_build.defaults(obj.ReconstructionSfmRecipeDropDown.Value);
            end
        end

        function reconstruction_calibration_changed(obj)
            % A calibration chosen in step 2: kept, and its camera set shown
            obj.reconstruction_save_sfm_choice();
            obj.reconstruction_show_camset();
        end

        function reconstruction_fill_from_cut(obj)
            % Step 2 from the cut just made: its reconstruction images
            % folder and the regions file written next to it. Kept in the
            % dataset's tab state; Browse still overrides
            filled = false;
            if isfield(obj.host.data, 'cut_folders_made') && isfield(obj.host.data.cut_folders_made, 'reconstruction') && ...
                    isfolder(obj.host.data.cut_folders_made.reconstruction.path)
                obj.ReconstructionImagesField.Value = obj.host.data.cut_folders_made.reconstruction.path;
                filled = true;
            end
            if isfield(obj.host.data, 'cut_roi_json') && ~isempty(obj.host.data.cut_roi_json) && ...
                    exist(obj.host.data.cut_roi_json, 'file') == 2
                obj.ReconstructionRoiField.Value = obj.host.data.cut_roi_json;
                filled = true;
            end
            if filled
                obj.reconstruction_save_step2_inputs();
                obj.reconstruction_update_journey();
                obj.reconstruction_update_enablement();
            end
        end

        function reconstruction_save_step2_inputs(obj)
            % Step 2's two paths in the dataset's tab-state.json
            if isempty(obj.reconstruction_tab), return; end
            try
                obj.reconstruction_tab.set_step2_inputs(struct( ...
                    'images_dir', strtrim(obj.ReconstructionImagesField.Value), ...
                    'roi_json', strtrim(obj.ReconstructionRoiField.Value)));
            catch
                % the tab state could not be written: the fields still hold the paths
            end
        end

        function reconstruction_restore_step2_inputs(obj, s)
            % Empty step 2 fields from the tab state, else from this
            % session's cut; only paths that are still there
            if isempty(strtrim(obj.ReconstructionImagesField.Value)) && isempty(strtrim(obj.ReconstructionRoiField.Value))
                if isstruct(s) && isfield(s, 'step2_inputs') && isstruct(s.step2_inputs)
                    si = s.step2_inputs;
                    if isfield(si, 'images_dir') && ischar(si.images_dir) && isfolder(si.images_dir)
                        obj.ReconstructionImagesField.Value = si.images_dir;
                    end
                    if isfield(si, 'roi_json') && ischar(si.roi_json) && exist(si.roi_json, 'file') == 2
                        obj.ReconstructionRoiField.Value = si.roi_json;
                    end
                end
                if isempty(strtrim(obj.ReconstructionImagesField.Value)) && isempty(strtrim(obj.ReconstructionRoiField.Value))
                    obj.reconstruction_fill_from_cut();
                end
            elseif ~(isstruct(s) && isfield(s, 'step2_inputs'))
                % Filled before a dataset was bound (a cut, or typed): kept
                % now, so a restart finds them
                obj.reconstruction_save_step2_inputs();
            end
        end

        function reconstruction_save_sfm_choice(obj)
            % Keep the step 2 choice in the dataset's tab-state.json
            if isempty(obj.reconstruction_tab), return; end
            obj.reconstruction_tab.set_sfm_choice(struct( ...
                'sparse_source', obj.reconstruction_sparse_source(), ...
                'recipe', obj.ReconstructionSfmRecipeDropDown.Value, ...
                'recipe_file', obj.reconstruction_sfm_recipe_file, ...
                'calibration', obj.ReconstructionCalibrationDropDown.Value));
        end

        function reconstruction_calibration_window_done(obj, after_done)
            % After a calibration in the calibration window: the list is
            % refreshed, and one that may give mm (PASSED or WARNED) is
            % chosen under Calibration (gives mm), so a Run started next
            % gives mm. A calibration started after the cut
            % (rabbit_calibration_scale.offer_after_cut) goes the same way,
            % so it counts as run here and is not run again.
            % after_done (optional): called last with the
            % window, whatever the result.
            % The History line names the verdict. LastOk only says that
            % pyCamSet finished, so it would log a FAILED calibration as
            % passed.
            if nargin < 2, after_done = []; end
            obj.reconstruction_refresh_calibrations();
            w = obj.reconstruction_calibration_window;
            if ~isempty(w) && isvalid(w)
                if w.LastOk && ~isempty(w.LastDir)
                    [~, cal_id] = fileparts(w.LastDir);
                    obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = ...
                        sprintf('Calibration %s: %s.', cal_id, obj.reconstruction_calibration_status(w.LastDir));
                else
                    obj.host.history_field.Value{length(obj.host.history_field.Value)+1,1} = 'Calibration did not finish.';
                end
            end
            if ~isempty(w) && isvalid(w) && w.LastOk && ~isempty(w.LastDir)
                [~, id] = fileparts(w.LastDir);
                dd = obj.ReconstructionCalibrationDropDown;
                if any(strcmp(dd.ItemsData, id)) && ~strcmp(dd.Value, id)
                    dd.Value = id;
                    obj.reconstruction_calibration_changed();
                    obj.Step2StatusChip.Text = sprintf('Calibration (gives mm) is now %s (%s).', id, ...
                        obj.reconstruction_calibration_status(w.LastDir));
                end
            end
            if ~isempty(after_done)
                after_done(w);
            end
        end

        function tf = reconstruction_has_dataset(obj)
            % A dataset is bound (a recording is loaded), for rabbit_calibration_scale
            tf = ~isempty(obj.reconstruction_tab);
        end

        function root = reconstruction_calibration_root(obj)
            % This recording's calibrations folder; '' with no dataset bound
            root = '';
            if ~isempty(obj.reconstruction_tab)
                root = obj.reconstruction_tab.calibration_root();
            end
        end

        function status = reconstruction_calibration_status(obj, cal_dir) %#ok<INUSL>
            % PASSED, WARNED or FAILED, from a calibration's verdict.json
            status = 'no verdict';
            try
                v = rabbit_calibration.read_json(fullfile(cal_dir, 'verdict.json'));
                status = char(v.status);
            catch
            end
        end

        function reconstruction_refresh_calibrations(obj)
            % The calibrations of this dataset folder that may give mm
            dd = obj.ReconstructionCalibrationDropDown;
            keep = dd.Value;
            items = {'None (model units)'};
            data = {''};
            if ~isempty(obj.reconstruction_tab)
                L = obj.reconstruction_tab.calibration_list();
                L = L([L.metric_allowed]);
                % Short names: the drop-down would cut
                % "cal_cut_tiffs_calibr...", hiding which calibration it is;
                % from the recording's time stamp on, "...14h-12m-15s_03
                % (WARNED)". The id stays the item's data.
                short = regexprep({L.label}, '^\S*?(\d+h-\d+m-\d+s\S*)', [char(8230) '$1']);
                % The drop-down still cuts that, so its number and status
                % only, "..._03 (WARNED)", as Results names
                % the calibration ("_03"), unless two would read the same
                tiny = regexprep({L.label}, '^\S*?(_\d+)(\s|$)', [char(8230) '$1$2']);
                if numel(unique(tiny)) == numel(tiny), short = tiny; end
                items = [items, short];
                data = [data, {L.id}];
            end
            dd.Items = items;
            dd.ItemsData = data;
            if any(strcmp(data, keep))
                dd.Value = keep;
            else
                dd.Value = '';
            end
            obj.reconstruction_show_camset();
        end

        function [cal_dir, go, date_note, differs] = reconstruction_calibration_for_run(obj)
            % The folder of the chosen calibration, re-read at click time.
            % A calibration from another day may be used, but only after
            % saying so; go is false when the user stops there, and the run
            % records the choice (differs, date_note). A date that is unknown
            % is not asked about: date_note goes on record.
            cal_dir = '';
            go = true;
            date_note = '';
            differs = false;
            id = obj.ReconstructionCalibrationDropDown.Value;
            if isempty(id), return; end
            L = obj.reconstruction_tab.calibration_list();
            k = find(strcmp({L.id}, id), 1);
            if isempty(k) || ~L(k).metric_allowed
                go = false;
                obj.reconstruction_refresh_calibrations();
                uialert(obj.host.opticalmappingUIFigure, sprintf(['The calibration %s is no longer available or ' ...
                    'did not pass its checks. Choose another, or None.'], id), 'Calibration');
                return;
            end
            cal_dir = L(k).dir;
            try
                spec = rabbit_calibration.read_json(fullfile(cal_dir, 'spec.json'));
                r = spec.recordings;
                if iscell(r), r = [r{:}]; end
                om = fullfile(obj.host.file_info.path, obj.host.file_info.file);
                [same, txt, date_note] = rabbit_calibration.session_check({r.path}, om, ...
                    rabbit_calibration.recording_dates(r));
            catch ME
                same = true;
                txt = '';
                date_note = sprintf('The dates of the recordings are unknown: %s', ME.message);
            end
            if ~same
                choice = uiconfirm(obj.host.opticalmappingUIFigure, [txt ' The rig may have changed in between; ' ...
                    'the run compares the two rigs and stays in model units if they disagree.'], 'Calibration', ...
                    'Options', {'Use it', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                go = strcmp(choice, 'Use it');
                differs = true;
                date_note = strtrim(sprintf('%s Used after the question at Run. %s', txt, date_note));
            end
        end

        function cal_dir = reconstruction_pick_calibration(obj, title)
            % The calibration chosen in step 2 or another one picked from this
            % recording's calibrations folder (any verdict, so a failed
            % calibration can be opened too); '' = none
            cal_dir = '';
            root = obj.reconstruction_tab.calibration_root();
            id = obj.ReconstructionCalibrationDropDown.Value;
            if ~isempty(id) && isfolder(fullfile(root, id))
                answer = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['Use the calibration chosen under ' ...
                    'Calibration (gives mm), %s, or choose another one (failed ones too)?'], id), title, ...
                    'Options', {sprintf('Use %s', id), 'Choose another...', 'Cancel'}, 'DefaultOption', 1, ...
                    'CancelOption', 3);
                if strcmp(answer, 'Cancel'), return; end
                if startsWith(answer, 'Use ')
                    cal_dir = fullfile(root, id);
                    return;
                end
            end
            if ~isfolder(root)
                uialert(obj.host.opticalmappingUIFigure, ['This recording has no calibrations yet. Press Calibrate... first: ' ...
                    'it makes the views of the calibration recordings, whether or not the calibration passes.'], title);
                return;
            end
            p = uigetdir(root, sprintf('%s: choose a calibration (cal_...)', title));
            if isequal(p, 0), return; end
            if exist(fullfile(p, 'spec.json'), 'file') ~= 2
                uialert(obj.host.opticalmappingUIFigure, sprintf('%s is not a calibration made by this app (no spec.json).', p), title);
                return;
            end
            cal_dir = p;
        end

        function ReconstructionPycamsetGuiButtonPushed(obj)
            % Open the pyCamSet GUI at Phase 1 on the tiles of a calibration's
            % fit recording; the app does not wait for it
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'pyCamSet');
                return;
            end
            cal_dir = obj.reconstruction_pick_calibration('Open in pyCamSet');
            if isempty(cal_dir), return; end
            [~, cal_id] = fileparts(cal_dir);
            % Said before the GUI starts, so the note is not hidden behind it
            go = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['The pyCamSet GUI will open at Phase 1 on the cube ' ...
                'recording of calibration %s, with the same views and target. Go through the phases there and ' ...
                'export a camera set (.camset); then press Link camera set... here to check it and use it.'], cal_id), ...
                'Open in pyCamSet', 'Options', {'Open', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
            if ~strcmp(go, 'Open'), return; end
            busy = uiprogressdlg(obj.host.opticalmappingUIFigure, 'Title', 'pyCamSet', ...
                'Message', 'Writing the views of the calibration recording...', 'Indeterminate', 'on');
            try
                [ok, err, gui_dir] = obj.reconstruction_tab.open_pycamset_gui(cal_dir);
            catch ME
                ok = false; err = ME.message; gui_dir = '';
            end
            close(busy);
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, err, 'pyCamSet');
                return;
            end
            obj.Step2StatusChip.Text = sprintf('pyCamSet GUI opened on %s (its messages: pycamset_gui.log in %s)', ...
                cal_id, gui_dir);

        end

        function ReconstructionCamsetButtonPushed(obj)
            % Link a camera set made in the pyCamSet GUI: it is checked on the
            % calibration recordings it was made from and, if it passes, chosen
            % under Calibration (gives mm)
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'pyCamSet camera set');
                return;
            end
            start_dir = fullfile(obj.reconstruction_tab.calibration_root(), 'pycamset_gui');
            if ~isfolder(start_dir), start_dir = obj.reconstruction_tab.calibration_root(); end
            [f, p] = uigetfile({'*.camset', 'pyCamSet camera set (*.camset)'}, 'pyCamSet camera set', ...
                [start_dir filesep]);
            if isequal(f, 0), return; end
            camset = fullfile(p, f);
            base = obj.reconstruction_tab.camset_base(camset);
            if isempty(base)
                % Not saved in a folder Open in pyCamSet... made (or that
                % calibration moved): the user says which recordings to use
                ans_ = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['%s was not saved in a folder made by Open in ' ...
                    'pyCamSet..., so the app does not know which calibration recordings it was made on. ' ...
                    'Choose the calibration whose recordings it is to be checked on next.'], f), ...
                    'Link camera set', 'Options', {'Choose...', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, ...
                    'Icon', 'warning');
                if ~strcmp(ans_, 'Choose...'), return; end
                base = obj.reconstruction_pick_calibration('Link camera set');
                if isempty(base), return; end
            end
            [~, base_id] = fileparts(base);
            busy = uiprogressdlg(obj.host.opticalmappingUIFigure, 'Title', 'pyCamSet camera set', ...
                'Message', sprintf('Checking %s on the recordings of calibration %s (a few minutes)...', f, base_id), ...
                'Indeterminate', 'on', 'Cancelable', 'on');
            % Cancel reaches the job as the calibration window's does
            tab = obj.reconstruction_tab;
            watch = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.5, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) obj.reconstruction_camset_cancel(busy, tab));
            start(watch);
            try
                [ok, err, cal_dir, lines] = tab.import_camset(camset, base);
            catch ME
                ok = false; err = ME.message; cal_dir = ''; lines = {};
            end
            stop(watch); delete(watch);
            close(busy);
            obj.reconstruction_refresh_calibrations();
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, sprintf('The camera set could not be used: %s', err), 'pyCamSet camera set');
                return;
            end
            [~, id] = fileparts(cal_dir);
            dd = obj.ReconstructionCalibrationDropDown;
            before = dd.Value;
            if isempty(before), before = 'None (model units)'; end
            if any(strcmp(dd.ItemsData, id))
                dd.Value = id;
                obj.reconstruction_save_sfm_choice();
                obj.reconstruction_show_camset();
                head = sprintf(['Linked as calibration %s. Calibration (gives mm) is now %s (it was %s); ' ...
                    'choose another there to change it back.'], id, id, before);
            else
                head = sprintf('Checked as calibration %s, but it may not give mm (see why below).', id);
            end
            uialert(obj.host.opticalmappingUIFigure, strjoin([{head}, lines(:)'], newline), 'pyCamSet camera set', 'Icon', 'info');
        end

        function reconstruction_camset_cancel(obj, busy, tab) %#ok<INUSL>
            % Pass a Cancel of the Link camera set... progress window to the job
            try
                if isvalid(busy) && busy.CancelRequested
                    tab.cancel_calibration();
                    busy.Message = 'Cancelling...';
                end
            catch
                % the window closed between two ticks
            end
        end

        function reconstruction_show_camset(obj)
            % The camera set field shows the linked camera set of the
            % calibration chosen now, and nothing for any other choice
            path = '';
            tip = {'A camera set exported from the pyCamSet GUI. Linking it checks it on the calibration recordings and adds it to Calibration (gives mm).'};
            id = obj.ReconstructionCalibrationDropDown.Value;
            if ~isempty(id) && ~isempty(obj.reconstruction_tab)
                try
                    c = rabbit_calibration.read_json(fullfile(obj.reconstruction_tab.calibration_root(), id, 'calibration.json'));
                    if isfield(c, 'imported_camset')
                        path = char(c.imported_camset.path);
                        tip = {sprintf('Calibration %s takes its cameras from this camera set (sha256 %s).', id, ...
                            char(c.imported_camset.sha256))};
                    end
                catch
                    path = '';
                end
            end
            obj.ReconstructionCamsetField.Value = path;
            obj.ReconstructionCamsetField.Tooltip = tip;
        end

        function ReconstructionCalibrateButtonPushed(obj, after_done)
            % Open the calibration window. The tile columns come from the
            % ROI file, so that needs choosing first.
            % after_done (optional): called with the window after
            % a calibration; rabbit_calibration_scale passes one that fills
            % the Conduction Velocity tab's scale
            if nargin < 2, after_done = []; end
            if isempty(obj.reconstruction_tab)
                uialert(obj.host.opticalmappingUIFigure, 'Load a dataset first (File > Load file).', 'Calibration');
                return;
            end
            roi = obj.ReconstructionRoiField.Value;
            if isempty(strtrim(roi)) || exist(roi, 'file') ~= 2
                uialert(obj.host.opticalmappingUIFigure, ['The regions file is needed first (step 2): the calibration uses ' ...
                    'the same four views as the recordings. The cut after Define regions fills it in.'], 'Calibration');
                return;
            end
            [recipe, r_err] = obj.reconstruction_sfm_recipe();
            if isempty(recipe)
                uialert(obj.host.opticalmappingUIFigure, r_err, 'Sparse model recipe');
                return;
            end
            try
                % The tile bounds and frame size of the reconstruction frame,
                % as the run will use them: from the images' cut manifest,
                % else the ROI file mapped with its fov_mapping. The ROI
                % file's own are the OM recording's when that is a crop.
                [fit_ok, fit_err, rr] = rabbit_sfm_build.resolve(recipe, struct( ...
                    'images_dir', obj.ReconstructionImagesField.Value, 'roi_json', roi));
                if ~fit_ok, error('%s', fit_err); end
                [frame_hw, roi_hw, f_err] = rabbit_calibration.frame_size(rr, roi);
                if ~isempty(f_err), error('%s', f_err); end
                [tile_bounds, b_err] = rabbit_calibration.tile_bounds(rr);
                if ~isempty(b_err), error('%s', b_err); end
                b_err = rabbit_calibration.check_roi_bounds(tile_bounds, roi);
                if ~isempty(b_err), error('%s', b_err); end
                % The reconstruction recording, to place calibration
                % frames of another area of interest
                ref = rabbit_calibration.reference_source(obj.ReconstructionImagesField.Value, roi);
                obj.reconstruction_calibration_window = rabbit_calibration_dialog(obj.reconstruction_tab, ...
                    tile_bounds, recipe.camera.focal_prior_px, ...
                    @() obj.reconstruction_calibration_window_done(after_done), frame_hw, roi_hw, ref, roi, ...
                    struct('calibration_path', char(obj.host.data.calibration_source), ...
                    'calibration_fov_mapping', obj.host.data.calibration_fov_mapping, ...
                    'fov_mapping', obj.host.data.reconstruction_fov_mapping), ...   % the line-ups held now
                    obj.reconstruction_calibration_prefill());   % the region dialog's calibration recording, listed already   % roi: the region dialog's line-ups
            catch ME
                uialert(obj.host.opticalmappingUIFigure, ME.message, 'Calibration');
            end
        end

        function p = reconstruction_calibration_prefill(obj)
            % The calibration recording(s) of the region dialog, for the
            % calibration window's list
            p = {};
            % the calibration cut folder (view1..view4) when the cut made
            % one, else the recording
            if isfield(obj.host.data, 'cut_folders_made') && isfield(obj.host.data.cut_folders_made, 'calibration') && ...
                    exist(fullfile(obj.host.data.cut_folders_made.calibration.path, 'cut_locations_per_view.json'), 'file') == 2
                p = {obj.host.data.cut_folders_made.calibration.path};
                return;
            end
            if isfield(obj.host.data, 'calibration_source') && ~isempty(obj.host.data.calibration_source)
                c = cellstr(obj.host.data.calibration_source);
                p = c(cellfun(@(x) exist(x, 'file') == 2 || isfolder(x), c));
            end
        end

        function reconstruction_restore_sfm_choice(obj, s)
            % Step 2 choice from the tab state; a dataset without one
            % builds the sparse model from the images. Using an existing
            % model is an option, never a requirement
            source = 'built';
            recipe = 'rabbit_4view_v1';
            file = '';
            if isstruct(s) && isfield(s, 'sfm') && isstruct(s.sfm) && isscalar(s.sfm)
                if isfield(s.sfm, 'sparse_source') && any(strcmp(s.sfm.sparse_source, {'built', 'supplied'}))
                    source = s.sfm.sparse_source;
                end
                if isfield(s.sfm, 'recipe_file') && ischar(s.sfm.recipe_file) && ...
                        ~isempty(s.sfm.recipe_file) && exist(s.sfm.recipe_file, 'file') == 2
                    recipe = 'custom';
                    file = s.sfm.recipe_file;
                end
            end
            obj.ReconstructionSparseSourceDropDown.Value = source;
            obj.ReconstructionSfmRecipeDropDown.Value = recipe;
            obj.reconstruction_sfm_recipe_file = file;
            obj.reconstruction_show_sparse_source();
            obj.reconstruction_refresh_calibrations();
            if isstruct(s) && isfield(s, 'sfm') && isstruct(s.sfm) && isscalar(s.sfm) && ...
                    isfield(s.sfm, 'calibration') && ischar(s.sfm.calibration) && ...
                    any(strcmp(obj.ReconstructionCalibrationDropDown.ItemsData, s.sfm.calibration))
                obj.ReconstructionCalibrationDropDown.Value = s.sfm.calibration;
            end
        end

        function ReconstructionSfmDetailsButtonPushed(obj)
            % The recipe's settings and its COLMAP commands (with the
            % path tokens left in), read-only, with "Save copy as JSON..."
            [recipe, err] = obj.reconstruction_sfm_recipe();
            if isempty(recipe)
                uialert(obj.host.opticalmappingUIFigure, err, 'Sparse model recipe');
                return;
            end
            lines = rabbit_sfm_build.describe(recipe);
            lines{end+1} = '';
            lines{end+1} = ['Methods: ' obj.reconstruction_tab.stage_citation_short('sparse_build')];
            fig = uifigure('Name', 'Sparse model recipe', 'Position', [100 100 900 520]);
            gl = uigridlayout(fig, [2 2]);
            gl.RowHeight = {'1x', 30};
            gl.ColumnWidth = {'1x', 180};
            ta = uitextarea(gl, 'Value', lines, 'Editable', 'off');
            ta.Layout.Row = 1;
            ta.Layout.Column = [1 2];
            b = uibutton(gl, 'push', 'Text', 'Save copy as JSON...', ...
                'ButtonPushedFcn', @(~, ~) obj.reconstruction_save_sfm_recipe_copy(recipe));
            b.Layout.Row = 2;
            b.Layout.Column = 2;
        end

        function reconstruction_save_sfm_recipe_copy(obj, recipe)
            % Write the recipe as JSON to edit and load back with
            % "Custom recipe file..."
            [f, pth] = uiputfile('*.json', 'Save the sparse model recipe', [recipe.name '_copy.json']);
            if isequal(f, 0), return; end
            try
                rabbit_sfm_build.write_text(fullfile(pth, f), rabbit_sfm_build.to_json(recipe));
            catch ME
                uialert(obj.host.opticalmappingUIFigure, ME.message, 'Sparse model recipe');
            end
        end

        % Helper: apply a validated manifest to the tab
        function reconstruction_apply_manifest(obj, info)
            obj.ReconstructionDatasetField.Value = fullfile(info.dataset_root, [info.dataset_stem '.matom']);
            obj.reconstruction_update_dataset_folders();
            obj.ReconstructionSparseField.Value = '';
            obj.ReconstructionImagesField.Value = '';
            obj.ReconstructionRoiField.Value = '';
            s = obj.reconstruction_tab.get_state();
            obj.reconstruction_show_tool_paths(s);
            [sync_ok, sync_err] = obj.reconstruction_sync_tool_paths();
            % Step 2 shows how the opened run got its sparse model
            if isfield(info, 'manifest') && isstruct(info.manifest)
                src = obj.reconstruction_tab.sparse_source_for_manifest(info.manifest);
                obj.ReconstructionSparseSourceDropDown.Value = src;
                try
                    obj.reconstruction_dense_by_source.(src) = rabbit_reconstruction_tab.dense_for_order( ...
                        obj.reconstruction_tab.stage_order_for_manifest(info.manifest));
                catch
                end
                obj.reconstruction_show_sparse_source();
                cs = obj.reconstruction_tab.cloud_source_for_manifest(info.manifest);
                if any(strcmp(cs, {'fused', 'apd'})) && strcmp(char(obj.ReconstructionCloudSourceDropDown.Enable), 'on')
                    obj.ReconstructionCloudSourceDropDown.Value = cs;
                end
            end
            obj.reconstruction_update_run_list();

            % Select info.run_id in ReconstructionRunList
            items = obj.ReconstructionRunList.Items;
            for k = 1:numel(items)
                if ~isempty(strfind(items{k}, info.run_id))
                    obj.ReconstructionRunList.Value = items{k};
                    break;
                end
            end

            % Truthful status rendering
            obj.reconstruction_render_status(info.run_id);
            obj.reconstruction_open_finished_run();

            % Visualise fields: the three manifest-resolved views.
            obj.VisualiseFusedField.Value = info.fused_ply;
            obj.VisualiseRebuiltField.Value = info.rebuilt_ply;
            obj.VisualiseProjectedField.Value = info.projected_ply;
            if info.dataset_path_mismatch
                % The recorded folder cut from the left, in full in the tooltip
                obj.VisualiseStatusText.Value = {sprintf('Run %s opened. The dataset has been moved or copied since the run (the run recorded %s).', ...
                    info.run_id, rabbit_reconstruction_tab.display_path(info.manifest.dataset.path, 60))};
                obj.VisualiseStatusText.Tooltip = {rabbit_reconstruction_tab.display_path(info.manifest.dataset.path)};
            elseif isfield(info, 'active_manifest_path') && ~isempty(strfind(info.active_manifest_path, 'manifest.v2.json'))
                cfx = '';
                if isfield(info, 'converted_from_prefix') && ~isempty(info.converted_from_prefix)
                    cfx = ' (from an updated copy of the run record)';
                end
                obj.VisualiseStatusText.Value = {sprintf('Run %s opened%s. Visualise shows every model of the run side by side: sparse points, dense clouds, mesh, activation map and OM video on the mesh.', info.run_id, cfx)};
            else
                obj.VisualiseStatusText.Value = {sprintf('Run %s opened. Visualise shows every model of the run side by side: sparse points, dense clouds, mesh, activation map and OM video on the mesh.', info.run_id)};
            end
            obj.reconstruction_update_journey();
            obj.reconstruction_update_enablement();
            if ~sync_ok
                obj.StepHeader3.Text = obj.steps_step_text(3, false, 'check failed: see message');
                obj.StepHeader3.Tooltip = {['Check tools failed: ' sync_err]};
            end
        end
    end

    % Contextual help, the progress window and other tab helpers
    % (they were in App Designer's "App creation and deletion" block)
    methods (Access = public)

        % Button pushed function: ReconstructionReprojectFilesButton
        function ReconstructionReprojectFilesButtonPushed(obj, ~, ~)
            % Reproject the current activation map, and the OM video if
            % wanted, onto a COLMAP model and mesh chosen by hand, outside
            % a pipeline run. rabbit_rhythm_reproject.run_from_app asks for
            % the files and whether to include the video.
            rabbit_rhythm_reproject.run_from_app(obj.host);
        end

        %% Plain names for the Reconstruction tab
        % The stage ids and stored statuses stay as they are in code,
        % manifests and logs; these only change what the user reads.
        function label = reconstruction_stage_label(obj, stage, stages)
            % stages (optional): the steps of the run the label is for, else
            % those in the step list. With the APDe-MVS steps there, the
            % COLMAP depth maps and fusion still run: the mesh step takes
            % which cameras see each point (fused-geometric.ply.vis) and the
            % alignment check its cloud from them, so they say so
            if nargin < 3
                stages = {};
                try
                    stages = obj.ReconstructionStageList.ItemsData;
                catch
                end
            end
            with_apd = iscell(stages) && any(strcmp(stages, 'apde_run'));
            if with_apd && strcmp(stage, 'patch_match_stereo')
                label = 'Depth maps (COLMAP, for the visibility check)';
                return;
            end
            if with_apd && strcmp(stage, 'stereo_fusion')
                label = 'Dense cloud (COLMAP fusion, for the visibility check)';
                return;
            end
            switch stage
                case 'sparse_prep',        label = 'Prepare images for the sparse model';
                case 'sparse_build',       label = 'Sparse model (COLMAP structure from motion)';
                case 'image_undistorter',  label = 'Undistort images (COLMAP)';
                case 'apde_scene_prep',    label = 'Prepare APDe-MVS scene';
                case 'apde_run',           label = 'Dense cloud (APDe-MVS)';
                case 'patch_match_stereo', label = 'Depth maps (COLMAP)';
                case 'stereo_fusion',      label = 'Dense cloud (COLMAP fusion)';
                case 'mesh_cleanup',       label = 'Clean cloud and build mesh';
                case 'alignment',          label = 'Check alignment';
                case 'reprojection',       label = 'Project optical mapping onto mesh';
                otherwise,                 label = char(stage);
            end
        end

        function label = reconstruction_status_label(obj, status) %#ok<INUSL>
            switch status
                case 'NOT_STARTED', label = 'NOT STARTED';
                case 'WARNED',      label = 'PASSED WITH WARNINGS';
                otherwise,          label = strrep(char(status), '_', ' ');
            end
        end

        function msg = reconstruction_plain_message(obj, err) %#ok<INUSL>
            % An error for the user without its leading code
            % ('analyse_om:Reconstruction:Xxx - '); the code stays in logs and manifests
            % An error id at the start of a message is left out (analyse_om:...,
            % or CD:... in older recorded messages)
            msg = regexprep(char(err), ['^(analyse_om|CD):[A-Za-z]+(:[A-Za-z]+)*\s*(' char(8212) '|-)\s*'], '');
        end

        function ok = reconstruction_mesh_choice_ok(obj, mesh_method, cloud_source)
            % The alpha shape uses which cameras saw each point, which only
            % the COLMAP cloud records
            ok = ~(strcmp(mesh_method, 'alpha') && strcmp(cloud_source, 'apd'));
            if ~ok
                uialert(obj.host.opticalmappingUIFigure, ['The alpha shape needs the COLMAP fused cloud ' ...
                    '(it uses which cameras saw each point). Choose the COLMAP cloud, or the membrane fit.'], ...
                    'Reconstruction');
            end
        end

        function cv = reconstruction_cv_map(obj)
            % The Conduction Velocity tab's map for the reprojection step:
            % rows x cols x 3 (row and column components, speed; m/s), or
            % [] when none was made (an all-NaN map, as Generate CV map
            % leaves when it is cancelled, counts as none)
            cv = [];
            try
                c = obj.host.processed_data.CV_map;
            catch
                return;
            end
            if ~isempty(c) && ndims(c) == 3 && size(c, 3) >= 3 && any(isfinite(c(:, :, 3)), 'all')
                cv = c;
            end
            % A CV map made from an
            % earlier activation map is not projected; History says why
            why = rabbit_cv_map.stale(obj.host);
            if ~isempty(cv) && ~isempty(why)
                cv = [];
                try
                    obj.host.history_field.Value{end + 1, 1} = ['Conduction velocity not projected: ' why];
                catch
                end
            end
        end

        function r = reconstruction_cv_settings_record(obj)
            % The CV map's settings under the names the CV projection's
            % record keeps (rabbit_cv_map.record_fields); []
            % without a CV map's settings
            r = [];
            try
                if isfield(obj.host.processed_data, 'CV_settings')
                    r = rabbit_cv_map.record_fields(obj.host.processed_data.CV_settings);
                end
            catch
                r = [];
            end
        end

        function S = reconstruction_cv_pixel_um(obj)
            % Each pixel's size (um) as the CV map was made with it, for the
            % tilt-corrected surface speed; [] when it cannot be given per
            % view. The sizes kept with the CV map (rabbit_cv_map.pixel_um_map)
            S = rabbit_cv_map.pixel_um_map(obj.host);
        end

        function prm = reconstruction_cv_parameters(obj)
            % How the CV map was made, for the run manifest
            prm = struct();
            try
                prm.method = char(obj.host.CV_method.Value);
                prm.distance_max = obj.host.distancemax.Value;
                prm.time_max = obj.host.timemax.Value;
                prm.pixel_scale = obj.host.processed_data.scale;   % one value; NaN (null) when the views differ
                % The size of each view's pixels (um), View1 to
                % View4, and where each came from
                [v, src] = rabbit_calibration_scale.views(obj.host);
                prm.pixel_scale_views = v;
                prm.pixel_scale_sources = src;
                prm.pixel_scale_layout = rabbit_calibration_scale.layout(obj.host);
                % The Bayly settings the CV map was made with
                % (smoothing and the time window), else those set now
                s = [];
                if isfield(obj.host.processed_data, 'CV_settings'), s = obj.host.processed_data.CV_settings; end
                if isstruct(s)
                    prm.distance_max = s.distance_max_mm;
                    prm.time_max = s.time_max_ms;
                    if isfield(s, 'method') && ~isempty(s.method), prm.method = char(s.method); end   % the method the map was made with
                else
                    s = rabbit_cv_map.settings(obj.host);
                end
                prm.time_max_source = s.time_max_source;
                % The activation cut the
                % CV map was made with, and where it came from
                if isfield(s, 'activation_cut_ms')
                    prm.activation_cut_ms = s.activation_cut_ms;
                    if ~isfinite(prm.activation_cut_ms), prm.activation_cut_ms = []; end   % JSON: none
                    prm.activation_cut_source = s.activation_cut_source;
                end
                prm.smooth_activation = s.smooth_activation;
                prm.smooth_method = s.smooth_method;
                % Each view's activation spread of the map the
                % CV step used (the near-simultaneous activation warning)
                if isfield(obj.host.processed_data, 'CV_activation_spread')
                    prm.activation_spread = obj.host.processed_data.CV_activation_spread;
                end
                prm.units = 'm/s (mm/ms)';
                % the same settings under the names the CV projection's
                % record keeps
                rf = rabbit_cv_map.record_fields(s);
                if isstruct(rf)
                    for f = fieldnames(rf)', prm.(f{1}) = rf.(f{1}); end
                end
            catch
            end
        end

        function flipped = reconstruction_om_rows_flipped(obj)
            % Whether the loaded OM recording is upside down relative to
            % the cut images: the app loads FITS files flipped
            flipped = 'auto';
            if isfield(obj.host.file_info, 'type') && ~isempty(obj.host.file_info.type)
                flipped = strcmpi(obj.host.file_info.type, '.fits');
            end
        end

        function clean = reconstruction_run_consistent(obj, run_id)
            % Completion check of a COMPLETED run for the run list, kept
            % while the run record (manifest) and the output files do not
            % change. A check that fails is not kept, so it is tried again.
            [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
            run_dir = fullfile(ds_root, [ds_stem '.matom'], 'reconstruction', 'runs', run_id);
            d = [dir(fullfile(run_dir, 'manifest.json')); dir(fullfile(run_dir, 'manifest.v2.json')); ...
                dir(fullfile(run_dir, 'outputs', '**', '*'))];
            % Files only ('*' also lists files without an extension)
            d = d(~[d.isdir]);
            stamp = sum([d.datenum]) + sum([d.bytes]) + numel(d);
            cache = obj.reconstruction_consistency_cache;
            k = find(strcmp({cache.run_id}, run_id), 1);
            if ~isempty(k) && cache(k).stamp == stamp
                clean = cache(k).clean;
                return;
            end
            try
                [is_clean, ~] = obj.reconstruction_tab.reconstruction_completion_consistency(run_id);
                clean = ~isempty(is_clean) && islogical(is_clean) && is_clean;
            catch
                clean = true;
                return;
            end
            if isempty(k)
                k = numel(cache) + 1;
            end
            cache(k) = struct('run_id', run_id, 'stamp', stamp, 'clean', clean);
            obj.reconstruction_consistency_cache = cache;
        end

        function [mesh_method, cloud_source, go] = reconstruction_resume_mesh_choice(obj, run_id, first_stage)
            % The mesh method and dense cloud a resumed run uses: the ones
            % the run recorded when its meshing step ran, unless the user
            % chooses the current drop-down values instead. Only asked
            % when the resume starts at or before the meshing step; after
            % it the mesh is made and the recorded settings are kept.
            mesh_method = obj.ReconstructionMeshMethodDropDown.Value;
            cloud_source = obj.ReconstructionCloudSourceDropDown.Value;
            go = true;
            rec_method = '';
            rec_cloud = '';
            try
                [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
                m = obj.reconstruction_tab.read_manifest(fullfile(ds_root, [ds_stem '.matom'], ...
                    'reconstruction', 'runs', run_id));
                for k = 1:numel(m.stages)
                    if strcmp(m.stages(k).name, 'mesh_cleanup') && isstruct(m.stages(k).settings_resolved)
                        s = m.stages(k).settings_resolved;
                        if isfield(s, 'mesh_method'), rec_method = char(s.mesh_method); end
                        if isfield(s, 'cloud_source'), rec_cloud = char(s.cloud_source); end
                    end
                end
            catch
                rec_method = '';
            end
            stages = obj.reconstruction_tab.stage_order_or_legacy(run_id);
            % A run without APDe-MVS meshes the COLMAP cloud
            if strcmp(rabbit_reconstruction_tab.dense_for_order(stages), 'colmap')
                cloud_source = 'fused';
            end
            if find(strcmp(stages, first_stage), 1) > find(strcmp(stages, 'mesh_cleanup'), 1)
                if ~isempty(rec_method) && ~isempty(rec_cloud)
                    mesh_method = rec_method;
                    cloud_source = rec_cloud;
                end
                return;
            end
            if isempty(rec_method) || isempty(rec_cloud)
                go = obj.reconstruction_mesh_choice_ok(mesh_method, cloud_source);
                return;
            end
            if strcmp(rec_method, mesh_method) && strcmp(rec_cloud, cloud_source)
                return;
            end
            names = containers.Map({'membrane', 'alpha', 'fused', 'apd'}, ...
                {'membrane fit', 'alpha shape', 'COLMAP fused cloud', 'APDe-MVS cloud'});
            label = @(v) obj.value_or_none(v);
            if isKey(names, rec_method), rec_m = names(rec_method); else, rec_m = label(rec_method); end
            if isKey(names, rec_cloud), rec_c = names(rec_cloud); else, rec_c = label(rec_cloud); end
            choice = uiconfirm(obj.host.opticalmappingUIFigure, sprintf(['Run %s was meshed with the %s of the %s. ' ...
                'The drop-downs now say %s and %s. Which settings should the resumed run use?'], run_id, ...
                rec_m, rec_c, names(mesh_method), names(cloud_source)), 'Reconstruction resume', ...
                'Options', {'The run''s settings', 'The current choices', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            switch choice
                case 'The run''s settings'
                    mesh_method = rec_method;
                    cloud_source = rec_cloud;
                case 'The current choices'
                    go = obj.reconstruction_mesh_choice_ok(mesh_method, cloud_source);
                otherwise
                    go = false;
            end
        end

        function tip = reconstruction_static_tip(obj, name) %#ok<INUSL>
            % Description shown while a control is enabled. A disabled
            % control shows what is missing instead (reconstruction_gate_state).
            switch name
                case 'ReconstructionRunButton'
                    % names the control by its label
                    tip = ['Start a new run (6' char(8211) '10 steps, depending on the sparse model and ' ...
                        'Clouds to compute). A progress window shows each step.'];
                case 'ReconstructionSfmDetailsButton'
                    tip = 'Show the settings and COLMAP commands of the sparse model recipe, and save a copy to edit.';
                case 'ReconstructionResumeButton'
                    tip = 'Carry on the selected run from its first unfinished step. Finished steps are kept.';
                case 'ReconstructionCancelButton'
                    tip = ['Ask the running step to stop. The run is marked cancelled once the step has stopped. ' ...
                        'For an INTERRUPTED run, which nothing is running, close it instead.'];
                case 'ReconstructionReprojectButton'
                    tip = ['Redo projection: project the activation map onto the selected run''s mesh with ' ...
                        'RHYTHM (Gloschat et al. 2018), as its projection step, pending or done before. A COMPLETED ' ...
                        'run whose steps passed, with or without warnings, is projected again (e.g. to add the OM ' ...
                        'video); the earlier projection is kept in outputs/reprojection_NN.'];
                case 'ReconstructionVisualiseButton'
                    tip = 'Open the linked 3-D viewer for the selected run.';
                case 'ReconstructionCheckToolsButton'
                    tip = 'Check that every tool path is set and each tool can be found.';
                case 'ReconstructionCitationsButton'
                    tip = 'Show the methods used and their citations.';
                case 'ReconstructionSparseButton'
                    tip = 'Choose the COLMAP sparse model folder (cameras, images and points files).';
                case 'ReconstructionImagesButton'
                    tip = 'Choose the folder of reconstruction images (TIFF) named in the sparse model.';
                case 'ReconstructionRoiButton'
                    tip = 'Choose the regions file (JSON) that says where each view sits on the optical mapping image.';
                case 'ReconstructionRunList'
                    tip = 'Runs for this dataset, with their status. Select one to see its steps and outputs.';
                case {'TouchupPreviewButton', 'IntensityPreviewButton', 'AreaPreviewButton', 'SmoothPreviewButton'}
                    tip = 'Show the result on screen. Nothing is saved.';
                case {'TouchupApplyButton', 'IntensityApplyButton', 'AreaApplyButton', 'SmoothApplyButton'}
                    tip = 'Save the previewed result as a new copy. The source file is not changed.';
                case 'AreaSelectButton'
                    tip = 'Draw the area to remove in the 3-D view.';
                case 'SmoothSelectButton'
                    tip = 'Click the centre of the area to smooth in the 3-D view.';
                otherwise
                    tip = '';
            end
        end

        %% Progress dialog for Run, Resume and Reproject
        % run_pipeline is synchronous and calls progress_cb before and
        % after each step. The dialog shows step k of N; its Cancel button
        % sends the same request as the Step 4 Cancel button. A timer
        % checks the button, because the backend only pauses (and so lets
        % the timer run) while it waits for an external program.
        function progress = reconstruction_progress_open(obj, run_id, title)
            progress = struct('dlg', [], 'timer', []);
            try
                % The window is blocked while a run works; the title says
                % when it comes back
                progress.dlg = uiprogressdlg(obj.host.opticalmappingUIFigure, 'Title', ...
                    sprintf('%s (Help and the app are back when it ends)', title), ...
                    'Message', sprintf('Run %s: starting...', run_id), ...
                    'Indeterminate', 'on', 'Cancelable', 'on', 'CancelText', 'Cancel run');
            catch
                return;
            end
            dlg = progress.dlg;
            progress.timer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.5, ...
                'BusyMode', 'drop', 'Name', 'reconstruction_progress', ...
                'TimerFcn', @(t, ~) obj.reconstruction_progress_poll(t, dlg, run_id));
            start(progress.timer);
        end

        function reconstruction_progress_stage(obj, progress, run_id, stage, status)
            % The tab is updated as without a dialog, then the dialog.
            obj.reconstruction_update_stage_status(run_id, stage, status);
            dlg = progress.dlg;
            if isempty(dlg) || ~isvalid(dlg)
                return;
            end
            stages = obj.reconstruction_tab.stage_order_or_legacy(run_id);
            n = numel(stages);
            k = find(strcmp(stages, stage), 1);
            if isempty(k)
                return;
            end
            if strcmp(status, 'RUNNING')
                dlg.Indeterminate = 'off';
                dlg.Value = (k - 1) / n;
                msg = sprintf('Step %d of %d: %s', k, n, obj.reconstruction_stage_label(stage, stages));
                if dlg.CancelRequested
                    msg = sprintf('%s\nCancel requested. Waiting for the current step to stop...', msg);
                end
                dlg.Message = msg;
            else
                dlg.Value = k / n;
            end
        end

        function reconstruction_progress_poll(obj, t, dlg, run_id)
            % First Cancel click: the normal Cancel button path. After
            % that, the request is repeated, because a request made during
            % a MATLAB step is reset when the next step starts.
            try
                if isempty(dlg) || ~isvalid(dlg) || ~dlg.CancelRequested
                    return;
                end
                if isempty(t.UserData)
                    t.UserData = true;
                    dlg.Message = 'Cancel requested. Waiting for the current step to stop...';
                    obj.reconstruction_cancel_run(run_id);
                elseif strcmp(obj.cancel_pending_run_id, run_id)
                    obj.reconstruction_tab.request_cancel(run_id);
                end
            catch
            end
        end

        function reconstruction_progress_close(obj, progress) %#ok<INUSL>
            if ~isempty(progress.timer) && isvalid(progress.timer)
                stop(progress.timer);
                delete(progress.timer);
            end
            if ~isempty(progress.dlg) && isvalid(progress.dlg)
                close(progress.dlg);
            end
        end

        % ================================================================
        % Contextual help and the first-run checklist
        % ================================================================

        % ---- Context resolver ------------------------------------------
        function topic_id = reconstruction_help_topic_for_context(obj, explicit_id)
            %RECONSTRUCTION_HELP_TOPIC_FOR_CONTEXT  section 5.3 context-to-topic map.
            % Priority: a valid explicit request, then the visible
            % Reconstruction accordion, then the selected run.
            catalog = reconstruction_help_content();
            ids = {catalog.topics.id};
            if nargin > 1 && ~isempty(explicit_id) && any(strcmp(ids, explicit_id))
                topic_id = explicit_id;
                return;
            end
            topic_id = 'start-here';
            if isempty(obj.host.TabGroup) || ~isvalid(obj.host.TabGroup) || ...
                    isempty(obj.ReconstructionTab) || ...
                    ~isequal(obj.host.TabGroup.SelectedTab, obj.ReconstructionTab)
                return;
            end
            if obj.reconstruction_tools_open()
                topic_id = 'copy-on-write';
                return;
            end
            switch obj.reconstruction_step_open()
                case 1, topic_id = 'inputs'; return;
                case 2, topic_id = 'inputs'; return;
                case 3, topic_id = 'inputs'; return;
                case 4, topic_id = 'status-and-actions'; return;
            end
            run_id = obj.reconstruction_selected_run_id();
            if ~isempty(run_id)
                [status, ~] = obj.reconstruction_effective_status(run_id);
                if any(strcmp(status, {'COMPLETED', 'WARNED'}))
                    topic_id = 'visualisation';
                else
                    topic_id = 'status-and-actions';
                end
            end
        end

        % ---- Snapshot DTO ----------------------------------------------
        function snap = reconstruction_help_snapshot(obj)
            %RECONSTRUCTION_HELP_SNAPSHOT  one read-only snapshot of the run status.
            % All dynamic Help/checklist text and conditional citations consume
            % this snapshot; no run-state field or manifest is mutated here.
            snap = struct( ...
                'schema_version', 1, 'topic_id', 'start-here', ...
                'run_id', '', 'run_display', '', ...
                'status_authority', 'NONE', 'state_confirmed', false, ...
                'durable_status', '', 'provenance_kind', 'NONE', ...
                'owner_liveness', 'NONE', ...
                'stage_projection', struct([]), ...
                'artifact_projection', struct([]), ...
                'gate_projection', struct([]), ...
                'action_id', '', 'reason_code', '', ...
                'warning_codes', {{}}, 'manifest_digest', '', ...
                'executed_method_keys', {{}}, ...
                'checklist_lines', {{}}, 'dynamic_note', '');

            try
                g = obj.reconstruction_gate_state();
                snap.gate_projection = g;
                snap.topic_id = obj.reconstruction_help_topic_for_context('');
                snap.checklist_lines = { ...
                    ['1. Data: ' g.step1_note], ...
                    ['2. Inputs: ' g.step2_note], ...
                    ['3. Tools: ' g.step3_note], ...
                    ['4. Run: ' g.step4_note]};
                switch snap.topic_id
                    case 'inputs'
                        snap.dynamic_note = sprintf('Dataset: %s; inputs: %s; tools: %s.', ...
                            g.step1_note, g.step2_note, g.step3_note);
                    case 'stages',             snap.dynamic_note = g.step4_note;
                    case 'copy-on-write',      snap.dynamic_note = g.touchup_tip;
                    case 'status-and-actions', snap.dynamic_note = g.step4_note;
                    case 'visualisation'
                        snap.dynamic_note = obj.steps_ternary(g.visualise_ok, ...
                            'the selected run has results to show.', ...
                            'no selected run has results to show yet.');
                    otherwise
                        snap.dynamic_note = '';
                end
            catch
                snap.warning_codes{end+1} = 'GATE_PROJECTION_UNAVAILABLE';
                snap.checklist_lines = { ...
                    '1. Data: unknown', ...
                    '2. Inputs: unknown', ...
                    '3. Tools: unknown', ...
                    '4. Run: unknown'};
                snap.dynamic_note = 'the current status could not be read.';
            end

            if isempty(obj.reconstruction_tab)
                return;
            end
            run_id = obj.reconstruction_selected_run_id();
            if isempty(run_id)
                return;
            end
            snap.run_id = run_id;
            snap.run_display = ['Run ' run_id];

            try
                [status, durable] = obj.reconstruction_effective_status(run_id);
                snap.durable_status = status;
                if durable
                    if isempty(status)
                        snap.status_authority = 'UNREADABLE';
                    else
                        snap.status_authority = 'MANIFEST';
                    end
                else
                    snap.status_authority = 'TAB_NOT_DURABLE';
                end
                proj = obj.reconstruction_tab.reconstruction_stage_projection(run_id, []);
                snap.stage_projection = proj;
                snap.owner_liveness = proj.lock_state;
                snap.action_id = proj.action;
                if proj.is_unreadable
                    snap.reason_code = 'MANIFEST_UNREADABLE';
                elseif proj.has_out_of_order
                    snap.reason_code = 'OUT_OF_ORDER_STAGE_RECORDS';
                elseif ~isempty(proj.current_stage)
                    snap.reason_code = 'RUN_ACTIVE';
                elseif ~isempty(proj.first_resumable_stage)
                    snap.reason_code = 'RESUME_AVAILABLE';
                elseif proj.all_completion_equivalent
                    snap.reason_code = 'RUN_COMPLETE';
                else
                    snap.reason_code = 'NO_SAFE_ACTION';
                end
                snap.state_confirmed = durable && ~proj.is_unreadable;
                if proj.is_unreadable
                    snap.warning_codes{end+1} = 'MANIFEST_UNREADABLE';
                end
                if proj.has_out_of_order
                    snap.warning_codes{end+1} = 'OUT_OF_ORDER_STAGE_RECORDS';
                end

                % Pass through only method keys recorded by executed stage
                % records.  Conditional citations are never inferred.
                keys = {};
                for sk = 1:numel(proj.stages)
                    rec = proj.stages(sk).stage_record;
                    if isempty(rec) || ~isstruct(rec), continue; end
                    if isfield(rec, 'citation_key') && ~isempty(rec.citation_key)
                        keys{end+1} = char(rec.citation_key); %#ok<AGROW>
                    end
                    if isfield(rec, 'citations') && iscell(rec.citations)
                        for ck = 1:numel(rec.citations)
                            if ischar(rec.citations{ck}) || isstring(rec.citations{ck})
                                keys{end+1} = char(rec.citations{ck}); %#ok<AGROW>
                            end
                        end
                    end
                end
                snap.executed_method_keys = unique(keys, 'stable');

                [ds_root, ds_stem] = fileparts(obj.ReconstructionDatasetField.Value);
                run_dir = fullfile(ds_root, [ds_stem '.matom'], ...
                    'reconstruction', 'runs', run_id);
                active_path = obj.reconstruction_tab.active_source_path(run_dir);
                if ~isempty(active_path)
                    [digest_ok, digest, digest_err] = ...
                        obj.reconstruction_tab.manifest_bytes_sha256(active_path);
                    if digest_ok
                        snap.manifest_digest = digest;
                    else
                        snap.warning_codes{end+1} = 'MANIFEST_DIGEST_UNAVAILABLE';
                        if ~isempty(digest_err), snap.state_confirmed = false; end
                    end
                    manifest = obj.reconstruction_tab.read_manifest(run_dir);
                    if isstruct(manifest) && isfield(manifest, 'manifest_schema')
                        snap.provenance_kind = char(manifest.manifest_schema);
                    end
                end

                [vis_ok, ~, vis] = ...
                    obj.reconstruction_tab.resolve_visualisation_context(run_id);
                if vis_ok
                    [panel_ok, ~, panels] = ...
                        obj.reconstruction_tab.visualisation_panel_model(vis);
                    snap.artifact_projection = struct( ...
                        'context', vis, 'panels', panels, 'confirmed', panel_ok);
                end
            catch
                snap.state_confirmed = false;
                snap.warning_codes{end+1} = 'SNAPSHOT_PROJECTION_UNAVAILABLE';
            end
        end

        % ---- Citation resolver -----------------------------------------
        function records = reconstruction_help_resolve_citations(obj, keys, snapshot)
            %RECONSTRUCTION_HELP_RESOLVE_CITATIONS  section 5.4 citation resolver.
            %  Resolves each requested key against the backend citations()
            %  table.  Never parses the citation text.  Returns a struct array
            %  with fields: key, display_reference, identifiers,
            %  conditional, executed, status, message.
            %
            %  Status values:
            %    RESOLVED                - key found, not conditional.
            %    CONDITIONAL_EXECUTED    - conditional key with execution evidence.
            %    CONDITIONAL_NOT_RECORDED - conditional key, no evidence.
            %    UNRESOLVED              - key absent from backend table.
            if nargin < 3, snapshot = struct(); end
            if nargin < 2 || isempty(keys), records = struct([]); return; end
            if ~iscell(keys), keys = {keys}; end

            % Conditional keys per the backend citations() docstring.
            CONDITIONAL_KEYS = {'colmap-glomap','colmap-vocabtree','sam', ...
                'poisson-2013','poisson-2006','icp','umeyama','blender', ...
                'meshlab'};

            % Build lookup from backend table.
            backend = obj.reconstruction_help_citation_adapter_store;
            if isempty(backend) && ~isempty(obj.reconstruction_tab)
                try
                    backend = obj.reconstruction_tab.citations();
                catch
                end
            end
            lut = struct();
            for k = 1:numel(backend)
                if isfield(backend(k), 'citation_key') && ...
                        isfield(backend(k), 'reference') && ...
                        ~isempty(backend(k).citation_key)
                    lut.(matlab.lang.makeValidName(backend(k).citation_key)) = backend(k);
                end
            end

            % Executed-method evidence from snapshot.
            exec_keys = {};
            if isstruct(snapshot) && isfield(snapshot, 'executed_method_keys') && ...
                    iscell(snapshot.executed_method_keys)
                exec_keys = snapshot.executed_method_keys;
            end
            % Methods that depend on the run's settings (APDe-MVS, membrane
            % fit or alpha shape) count as conditional once a run with
            % step records is selected
            if ~isempty(exec_keys)
                CONDITIONAL_KEYS = [CONDITIONAL_KEYS, {'apde-mvs', 'membrane-fit', 'alphashape'}];
            end

            records = struct( ...
                'key', {}, 'display_reference', {}, 'identifiers', {}, ...
                'conditional', {}, 'executed', {}, 'status', {}, 'message', {});

            for ki = 1:numel(keys)
                key = keys{ki};
                is_cond = ismember(key, CONDITIONAL_KEYS);
                is_exec = ismember(key, exec_keys);
                field   = matlab.lang.makeValidName(key);

                rec.key         = key;
                rec.identifiers = {};
                rec.conditional = is_cond;
                rec.executed    = is_exec;

                if isfield(lut, field)
                    bk = lut.(field);
                    rec.display_reference = bk.reference;
                    % Preserve structured identifiers when the approved
                    % backend record exposes them; never scrape the display
                    % reference or duplicate a bibliography here.
                    if isfield(bk, 'identifiers')
                        rec.identifiers = bk.identifiers;
                    end
                    if is_cond && ~is_exec
                        rec.status  = 'CONDITIONAL_NOT_RECORDED';
                        lead = regexp(bk.reference, '^.*?\d{4}', 'match', 'once');
                        if isempty(lead), lead = bk.reference; end
                        rec.message = sprintf('%s - not recorded for this run (the run did not use this method).', lead);
                    elseif is_cond
                        rec.status  = 'CONDITIONAL_EXECUTED';
                        rec.message = '';
                    else
                        rec.status  = 'RESOLVED';
                        rec.message = '';
                    end
                else
                    rec.display_reference = '';
                    rec.status  = 'UNRESOLVED';
                    rec.message = ['Citation unavailable for key ' key '.'];
                end

                records(end+1) = rec; %#ok<AGROW>
            end
        end

        function reconstruction_help_citation_adapter_set(obj, records)
            % Test hook accepts structured citation records only; production
            % defaults to reconstruction_tab.citations().
            if isempty(records) || isstruct(records)
                obj.reconstruction_help_citation_adapter_store = records;
            else
                error('Reconstruction:CitationAdapter', 'The citation adapter must be a struct array or empty.');
            end
        end

        % ---- Preference adapter ----------------------------------------
        function val = reconstruction_help_pref_get(obj, key)
            %RECONSTRUCTION_HELP_PREF_GET  Read one Help preference key.
            %  Returns logical scalar or [] on any error / malformed value.
            %  Namespace: analyse_optical_mapping_ReconstructionHelp.
            adapter = obj.reconstruction_help_pref_adapter_get();
            try
                val = adapter.get(key);
            catch
                val = [];
            end
            if ~islogical(val) || ~isscalar(val)
                val = [];
            end
        end

        function ok = reconstruction_help_pref_set(obj, key, value)
            %RECONSTRUCTION_HELP_PREF_SET  Write + read-back one preference key.
            %  Returns false on write failure or read-back mismatch.
            ok = false;
            if ~islogical(value) || ~isscalar(value), return; end
            adapter = obj.reconstruction_help_pref_adapter_get();
            try
                adapter.set(key, value);
                rb = adapter.get(key);
                ok = islogical(rb) && isscalar(rb) && (rb == value);
            catch
            end
        end

        function adapter = reconstruction_help_pref_adapter_get(obj)
            %RECONSTRUCTION_HELP_PREF_ADAPTER_GET  Return the active pref adapter.
            %  Product default: MATLAB getpref/setpref.  Tests inject an
            %  in-memory struct adapter via reconstruction_help_pref_adapter_set.
            if ~isempty(obj.reconstruction_help_pref_adapter_store)
                adapter = obj.reconstruction_help_pref_adapter_store;
            else
                ns = 'analyse_optical_mapping_ReconstructionHelp';
                adapter = struct();
                adapter.get = @(k) obj.reconstruction_help_pref_default_get(ns, k);
                adapter.set = @(k, v) obj.reconstruction_help_pref_default_set(ns, k, v);
            end
        end

        function reconstruction_help_pref_adapter_set(obj, adapter)
            %RECONSTRUCTION_HELP_PREF_ADAPTER_SET  Inject a test pref adapter.
            obj.reconstruction_help_pref_adapter_store = adapter;
        end

        function val = reconstruction_help_pref_default_get(~, ns, key)
            %RECONSTRUCTION_HELP_PREF_DEFAULT_GET  Read from MATLAB prefs.
            try
                if ispref(ns, key)
                    val = getpref(ns, key);
                else
                    val = [];
                end
            catch
                val = [];
            end
        end

        function reconstruction_help_pref_default_set(~, ns, key, value)
            %RECONSTRUCTION_HELP_PREF_DEFAULT_SET  Write to MATLAB prefs.
            try
                setpref(ns, key, value);
            catch
            end
        end

        % ---- Acknowledgement -------------------------------------------
        function should = reconstruction_help_should_auto_open(obj, journey)
            %RECONSTRUCTION_HELP_SHOULD_AUTO_OPEN  True if checklist not acknowledged.
            %  journey: 'fresh' or 'restore'.
            should = false;
            switch journey
                case 'fresh'
                    key = 'fresh_checklist_ack_v1';
                case 'restore'
                    key = 'restore_checklist_ack_v1';
                otherwise
                    return;
            end
            ack = obj.reconstruction_help_pref_get(key);
            % Unacknowledged when key is missing, malformed, or false.
            should = isempty(ack) || (ack == false);
        end

        function reconstruction_help_acknowledge(obj, journey, got_it)
            %RECONSTRUCTION_HELP_ACKNOWLEDGE  Persist checklist acknowledgement.
            %  got_it=true means the user dismissed with "Got it".
            %  A write failure shows a bounded copy; run state is unchanged.
            switch journey
                case 'fresh',   key = 'fresh_checklist_ack_v1';
                case 'restore', key = 'restore_checklist_ack_v1';
                otherwise, return;
            end
            if ~islogical(got_it) || ~isscalar(got_it), return; end
            ok = obj.reconstruction_help_pref_set(key, got_it);
            if ~ok && got_it && isvalid(obj.host.opticalmappingUIFigure)
                uialert(obj.host.opticalmappingUIFigure, ...
                    'Could not save checklist preference. This does not affect the run.', ...
                    'Reconstruction Help', 'Icon', 'info');
            end
        end

        % ---- First-run trigger -----------------------------------------
        function shown = reconstruction_maybe_show_first_run(obj, journey)
            %RECONSTRUCTION_MAYBE_SHOW_FIRST_RUN  First-use hint for the checklist.
            %  The checklist does not open by itself: until it is acknowledged, the Guide button reads
            %  "Guide: start here" and opens it. journey: 'fresh' or 'restore'.
            shown = false;
            if nargin < 2 || ~ischar(journey) || ~any(strcmp(journey, {'fresh', 'restore'})), return; end
            if ~obj.ReconstructionHelpStartupComplete, return; end
            shown = obj.reconstruction_help_update_hint();
        end

        function shown = reconstruction_help_update_hint(obj)
            % The Guide button shows a hint while the checklist of the
            % tab's route (new run or saved run) is not acknowledged
            shown = false;
            btn = obj.ReconstructionGuideButton;
            if isempty(btn) || ~isvalid(btn), return; end
            try
                shown = obj.reconstruction_help_should_auto_open(obj.reconstruction_help_journey());
            catch
                shown = false;
            end
            if shown
                btn.Text = 'Guide: start here';
                btn.FontWeight = 'bold';
                btn.Tooltip = {'Opens a short checklist for this tab. Press Got it there to hide this hint.'};
                obj.GridLayoutJ.ColumnWidth = {'1x', 130};
            else
                btn.Text = 'Guide';
                btn.FontWeight = 'normal';
                btn.Tooltip = {'Open help for the current reconstruction step or selected run.'};
                obj.GridLayoutJ.ColumnWidth = {'1x', 80};
            end
        end

        function journey = reconstruction_help_journey(obj)
            % The tab's route: a saved run that was opened, or a new run
            journey = obj.steps_ternary(obj.reconstruction_restore_mode, 'restore', 'fresh');
        end

        % ---- Help lifecycle --------------------------------------------
        function reconstruction_open_help(obj, topic_id, reason)
            %RECONSTRUCTION_OPEN_HELP  Open/raise the modeless Help figure.
            %  topic_id: one of the 11 catalog IDs.
            %  reason: 'manual', 'first-run', or context source label.
            if nargin < 2, topic_id = ''; end
            if nargin < 3, reason = 'manual'; end
            resolved_topic = obj.reconstruction_help_topic_for_context(topic_id);

            if isempty(obj.reconstruction_help_figure) || ...
                    ~isvalid(obj.reconstruction_help_figure)
                % Create modeless figure
                hf = uifigure('Visible', 'off');
                hf.Name          = 'Reconstruction Help';
                hf.Position      = [100 100 880 620];
                hf.Resize        = 'on';
                hf.WindowStyle   = 'normal';
                hf.CloseRequestFcn = @(~,~) obj.reconstruction_close_help();
                obj.reconstruction_help_figure = hf;
            end

            obj.reconstruction_render_help(resolved_topic);
            % OM_APP_HEADLESS=1 (scripts and tests): Help is built but stays hidden
            if ~strcmp(getenv('OM_APP_HEADLESS'), '1')
                figure(obj.reconstruction_help_figure);
                obj.reconstruction_help_figure.Visible = 'on';
            end
            if ~isempty(obj.reconstruction_help_topic_list) && ...
                    isvalid(obj.reconstruction_help_topic_list)
                focus(obj.reconstruction_help_topic_list);
            end
        end

        function reconstruction_render_help(obj, topic_id)
            %RECONSTRUCTION_RENDER_HELP  Render topic content into the Help figure.
            hf = obj.reconstruction_help_figure;
            if isempty(hf) || ~isvalid(hf), return; end

            catalog = reconstruction_help_content();
            snap    = obj.reconstruction_help_snapshot();

            % Find topic
            ids = {catalog.topics.id};
            idx = find(strcmp(ids, topic_id), 1);
            if isempty(idx), idx = 1; end
            t = catalog.topics(idx);

            % Determine journey for acknowledge button
            switch topic_id
                case 'fresh-checklist',   journey = 'fresh';
                case 'restore-checklist', journey = 'restore';
                otherwise,                journey = '';
            end

            % The grid and the topic list are made once and kept. Rebuilding
            % the list inside its own ValueChangedFcn deleted the list being
            % clicked, so a click often only greyed the new selection and the
            % page changed on the next click
            topic_list = obj.reconstruction_help_topic_list;
            if ~isempty(topic_list) && isvalid(topic_list) && isequal(ancestor(topic_list, 'figure'), hf)
                gl = topic_list.Parent;
                kids = gl.Children;
                delete(kids(kids ~= topic_list));
                gl.RowHeight = {22, '1x', 0, 30};
            else
                delete(hf.Children);
                gl = uigridlayout(hf);
                % The topic list is wide enough for every title
                gl.ColumnWidth = {240, '1x'};
                gl.RowHeight   = {22, '1x', 0, 30};
                % ItemsData keeps the topic ids; the list shows the titles
                topic_list = uilistbox(gl);
                topic_list.Items = {catalog.topics.title};
                topic_list.ItemsData = {catalog.topics.id};
                topic_list.Layout.Row = [1 4];
                topic_list.Layout.Column = 1;
                topic_list.ValueChangedFcn = ...
                    @(src,~) obj.reconstruction_help_topic_selected(src);
                obj.reconstruction_help_topic_list = topic_list;
            end
            if ~isequal(topic_list.Value, t.id)
                topic_list.Value = t.id;
            end

            % Title
            title_lbl = uilabel(gl);
            title_lbl.Text            = t.title;
            title_lbl.FontWeight      = 'bold';
            title_lbl.FontSize        = 14;
            title_lbl.Layout.Row      = 1;
            title_lbl.Layout.Column   = 2;

            % Body text
            body_area = uitextarea(gl);
            body_lines = t.body;
            % The status note belongs to the topic it was made for, not to
            % another topic opened from the list ("Now: Select a run with a mesh" on the steps page)
            if ~isempty(snap.dynamic_note) && strcmp(snap.topic_id, t.id)
                body_lines = [body_lines, {'', ['Now: ' snap.dynamic_note]}];
            end
            if ~isempty(journey)
                body_lines = [body_lines, {'', 'Where you are:'}, snap.checklist_lines];
            end
            body_area.Value           = body_lines;
            body_area.Editable        = 'off';
            body_area.Layout.Row      = 2;
            body_area.Layout.Column   = 2;

            % Citation display (if applicable)
            cit_lines = {};
            if ~isempty(t.citation_keys) && ~isempty(obj.reconstruction_tab)
                records = obj.reconstruction_help_resolve_citations(t.citation_keys, snap);
                for r = 1:numel(records)
                    switch records(r).status
                        case {'RESOLVED', 'CONDITIONAL_EXECUTED'}
                            cit_lines{end+1} = records(r).display_reference; %#ok<AGROW>
                        otherwise
                            cit_lines{end+1} = records(r).message; %#ok<AGROW>
                    end
                end
            end

            % Citation text area (row 3), hidden when the topic cites nothing
            cit_area = uitextarea(gl);
            if isempty(cit_lines)
                cit_area.Value = {''};
                cit_area.Visible = 'off';
            else
                cit_area.Value = cit_lines;
                gl.RowHeight{3} = 130;
            end
            cit_area.Editable      = 'off';
            cit_area.Layout.Row    = 3;
            cit_area.Layout.Column = 2;

            % Buttons row
            btn_gl = uigridlayout(gl);
            btn_gl.ColumnWidth = {'1x', 120, 120};
            btn_gl.RowHeight   = {'1x'};
            btn_gl.Layout.Row    = 4;
            btn_gl.Layout.Column = 2;
            btn_gl.Padding       = [0 0 0 0];

            % Close button
            close_btn = uibutton(btn_gl);
            close_btn.Text = 'Close';
            close_btn.Layout.Row    = 1;
            close_btn.Layout.Column = 3;
            close_btn.ButtonPushedFcn = @(~,~) obj.reconstruction_close_help();

            % "Got it" button (checklist topics only)
            if ~isempty(journey)
                show_again = uicheckbox(btn_gl);
                show_again.Text = 'Show this checklist next time';
                show_again.Value = false;
                show_again.Layout.Row = 1;
                show_again.Layout.Column = 1;
                obj.reconstruction_help_show_again_checkbox = show_again;
                gotit_btn = uibutton(btn_gl);
                gotit_btn.Text = 'Got it';
                gotit_btn.Layout.Row    = 1;
                gotit_btn.Layout.Column = 2;
                gotit_btn.ButtonPushedFcn = ...
                    @(~,~) obj.reconstruction_help_got_it(journey, show_again.Value);
            else
                obj.reconstruction_help_show_again_checkbox = [];
            end

            drawnow;
        end

        function reconstruction_close_help(obj)
            %RECONSTRUCTION_CLOSE_HELP  Close Help without writing acknowledgement.
            if ~isempty(obj.reconstruction_help_figure) && ...
                    isvalid(obj.reconstruction_help_figure)
                delete(obj.reconstruction_help_figure);
            end
            obj.reconstruction_help_figure = [];
        end

        function reconstruction_help_got_it(obj, journey, show_again)
            %RECONSTRUCTION_HELP_GOT_IT  Acknowledge + close.
            if nargin < 3, show_again = false; end
            obj.reconstruction_help_acknowledge(journey, ~logical(show_again));
            obj.reconstruction_close_help();
            obj.reconstruction_help_update_hint();
        end

        function reconstruction_help_topic_selected(obj, src)
            % Topic-list navigation remains inside the one modeless figure.
            if isempty(src) || ~isvalid(src), return; end
            obj.reconstruction_render_help(src.Value);
        end

        function reconstruction_help_end_programmatic_selection(obj)
            if obj.ReconstructionHelpProgrammaticSelectionDepth > 0
                obj.ReconstructionHelpProgrammaticSelectionDepth = ...
                    obj.ReconstructionHelpProgrammaticSelectionDepth - uint32(1);
            end
        end

        % ---- TabGroup selection guard ----------------------------------
        function reconstruction_fit_tab_height(obj, sel)
            % The Reconstruction tab gets the window's height, in front of
            % the image above it, so its steps are not a small scrolling
            % pane; the other tabs get their usual height back
            % The usual height is the app's own
            % (a third of the window, as a load sets it), not one kept
            % here: choosing a tab sets the tab group back to its
            % design-time height (230 px) before this runs, which would
            % leave a gap above the tabs or, kept, cover the image
            fig = obj.host.opticalmappingUIFigure;
            try
                pos = obj.host.TabGroup.Position;
                fs = fig.Position;
                usual = pos(4);
                try
                    if ~isempty(obj.host.figure_size), usual = floor(obj.host.figure_size(4) / 3); end
                catch
                    % a test double without figure_size
                end
                want = [pos(1) pos(2) pos(3) usual];
                if isequal(sel, obj.ReconstructionTab)
                    uistack(obj.host.TabGroup, 'top');   % first: uistack sets the size back
                    want(4) = max(usual, fs(4) - pos(2));
                end
                obj.host.TabGroup.Position = want;
                % the first tab choice after a load sets the size back once
                % more when the window is drawn: set it again after that
                drawnow;
                if any(abs(obj.host.TabGroup.Position - want) > 0.5), obj.host.TabGroup.Position = want; end
            catch
                % the layout is left as it is
            end
        end

        function TabGroupSelectionChanged(obj, event)
            %TABGROUPSELECTIONCHANGED  Contextual help auto-open guard.
            %  Only fires for genuine user selection (depth == 0).
            if ~isvalid(obj.host.TabGroup), return; end
            sel = obj.host.TabGroup.SelectedTab;
            if nargin > 1 && ~isempty(event) && isprop(event, 'NewValue')
                sel = event.NewValue;
            end
            if isempty(sel), return; end
            % At the end of this callback, after the Help has opened (its
            % opening sets the size back)
            fit_at_end = onCleanup(@() obj.reconstruction_fit_tab_height(sel)); %#ok<NASGU>
            if ~isequal(sel, obj.ReconstructionTab)
                obj.ReconstructionHelpFreshShownThisSelection = false;
                return;
            end
            if ~obj.ReconstructionHelpStartupComplete, return; end
            if obj.ReconstructionHelpProgrammaticSelectionDepth > 0, return; end
            if obj.ReconstructionHelpFreshShownThisSelection, return; end
            shown = obj.reconstruction_maybe_show_first_run('fresh');
            if shown
                obj.ReconstructionHelpFreshShownThisSelection = true;
            end
        end

        % ---- Menu/button callbacks ------------------------------------
        function ReconstructionHelpMenuSelected(obj, ~)
            %RECONSTRUCTIONHELPMENUSELECTED  Contextual help: File > Reconstruction Help.
            obj.reconstruction_open_help('', 'manual');
        end

        function ReconstructionGuideButtonPushed(obj, ~)
            %RECONSTRUCTIONGUIDEBUTTONPUSHED  Contextual help: Journey strip Guide button.
            % Until its checklist is acknowledged, Guide opens the checklist
            journey = obj.reconstruction_help_journey();
            if obj.reconstruction_help_should_auto_open(journey)
                obj.reconstruction_open_help([journey '-checklist'], 'first-run');
            else
                obj.reconstruction_open_help('', 'manual');
            end
        end

        % ================================================================
        % End of the contextual help
        % ================================================================
    end

    methods (Access = private)

        function place_child(~, child, anchor, where)
            % Move child just before or after anchor among their parent's
            % children, in the order they are shown
            parent = child.Parent;
            kids = parent.Children;
            % A menu lists its children last-made first; a tab group in order
            shown_reversed = isa(parent, 'matlab.ui.container.Menu');
            if shown_reversed, kids = flipud(kids); end
            kids(kids == child) = [];
            k = find(kids == anchor, 1);
            if strcmp(where, 'after'), k = k + 1; end
            kids = [kids(1:k - 1); child; kids(k:end)];
            if shown_reversed, kids = flipud(kids); end
            parent.Children = kids;
        end
    end

    methods (Static)
        function open_folder(folder)
            %% Show a folder in the system's file browser (Windows, macOS, Linux)
            % With OM_APP_HEADLESS=1 (scripts and tests) nothing is opened:
            % the request is printed instead.
            if strcmp(getenv('OM_APP_HEADLESS'), '1')
                fprintf('Headless: open folder %s\n', folder);
                return;
            end
            if ispc
                winopen(folder);
            elseif ismac
                system(sprintf('open "%s" &', folder));
            else
                system(sprintf('xdg-open "%s" &', folder));
            end
        end
    end
end
