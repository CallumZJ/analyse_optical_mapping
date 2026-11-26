%% Contextual Help and first-run guide
% Collin Snitchler
% 14.09.2026
% Static, archive and live GUI checks for the reconstruction Help content,
% the Help window and the first-run guide.
%  Tier-A cases are display-independent and run anywhere.
%  Tier-B cases require a display and are skipped under '-nodisplay'.
%
%  Usage (standalone):
%    matlab -batch "cd('<worktree>'); addpath('<worktree>'); probe_contextual_help"
%
%  Usage (via matlab.unittest):
%    matlab -batch "runtests('probe_contextual_help')"

classdef probe_contextual_help < matlab.unittest.TestCase

    % =====================================================================
    % Content catalogue (Tier-A)
    % =====================================================================
    methods (Test, TestTags = {'TierA', 'Help', 'Catalog'})

        function t01_catalog_returns_struct(tc)
            % [T01] reconstruction_help_content returns a struct.
            cat = reconstruction_help_content();
            tc.verifyClass(cat, 'struct', 'catalog must be a struct');
        end

        function t02_catalog_version_is_1(tc)
            % [T02] catalog.version == 1 (schema lock).
            cat = reconstruction_help_content();
            tc.verifyEqual(cat.version, 1, 'catalog.version must be 1');
        end

        function t03_catalog_has_12_topics(tc)
            % [T03] exactly 12 topics present ("Rhythm and conduction velocity"
            % is the twelfth).
            cat = reconstruction_help_content();
            tc.verifyEqual(numel(cat.topics), 12, ...
                'Catalog must have exactly 12 topics');
        end

        function t04_topic_ids_all_present(tc)
            % [T04] all required topic IDs present in exact order
            % (rhythm-and-cv after the Viewer).
            REQUIRED = { ...
                'start-here', 'fresh-checklist', 'restore-checklist', ...
                'inputs', 'stages', 'reconstruction-vs-reprojection', ...
                'status-and-actions', 'visualisation', 'rhythm-and-cv', 'copy-on-write', ...
                'limitations-and-resources', 'methods-and-citations'};
            cat = reconstruction_help_content();
            ids = {cat.topics.id};
            tc.verifyEqual(ids, REQUIRED, ...
                'Topic IDs must match required list in exact order');
        end

        function t04b_rhythm_topic_and_viewer_reference(tc)
            % [T04b] the topic "Rhythm and
            % conduction velocity" says what the marker changes (labels
            % only), when CV is apparent, the pixel size, the 3x3 median and
            % the 2-frame window, and image plane vs surface (and
            % that Nearest Neighbour is noise-sensitive, Bayly preferred); the Viewer
            % topic sends mm to the Help topic "What to supply" (calibration).
            cat = reconstruction_help_content();
            t = cat.topics(strcmp({cat.topics.id}, 'rhythm-and-cv'));
            tc.verifyNumElements(t, 1, 'rhythm-and-cv topic must exist once');
            tc.verifyEqual(t.title, 'Rhythm and conduction velocity');
            body = strjoin(t.body, ' ');
            % the rhythm changes no number but which
            % warnings appear; two speeds (image plane and surface); the
            % outlier warning, Remove local outliers' MAD option, Relative
            % to earliest and the per-face CSV; "3x3" with the
            % multiplication sign (the "label only" and "only the arrows'
            % direction is lifted" lines were stale)
            x3 = ['3' char(215) '3'];
            for w = {'It changes no number; it changes which warnings appear (paced: outlier; sinus: near-simultaneous)', ...
                    'adds the cycle to the activation row', ...
                    ['within the time the middle half of the view takes at 1.5 m/s (view size / 3; about 7' char(8211) '10 ms here'], ...   % Q2
                    'not true conduction', ...
                    'use a paced recording', 'Scale from calibration...', 'sizes on the heart surface of a run are in its Details', ...
                    [x3 ' median within each view'], 'two frame intervals', ...
                    'Two speeds: image plane (as on the 2-D tab; reads low where the surface tilts away) and surface speed', ...
                    '(tilt-corrected, same Jacobian as the arrows; uncertain on steep faces and with the pose). Colours stay image-plane.', ...
                    'flat-activation patches', ...
                    ... % the paced outlier rule and its words
                    'Outlier warning (paced): > 5 % of values above 1.5 m/s, or > 1 % above 5 m/s; quote the median and IQR', ...
                    'look at the red patches on the 2-D CV map (white faces on the 3-D CV panel) before removing anything', '3 MAD, edges too', 'Relative to earliest', ...
                    'Per-face CSV', 'activation_class, activation_views, cv_class, cv_views', ...
                    'Nearest Neighbour', 'noise-sensitive, and Bayly is preferred'}   % NN method
                tc.verifyTrue(contains(body, w{1}), sprintf('rhythm-and-cv must say "%s"', w{1}));
            end
            tc.verifyFalse(contains(body, 'label only'), 'R7: the rhythm is not a label only');
            tc.verifyFalse(contains(body, 'size / 3 mm/ms'), 'Q2: the limit in physics words, not "size / 3 mm/ms"');
            all_text = strjoin(cellfun(@(b) strjoin(b, ' '), {cat.topics.body}, 'UniformOutput', false), ' ');
            tc.verifyEmpty(regexp(all_text, '\<\dx\d\>', 'once'), 'R7: 3x3 written with the multiplication sign');
            lim = strjoin(cat.topics(strcmp({cat.topics.id}, 'limitations-and-resources')).body, ' ');
            tc.verifyTrue(contains(lim, 'within 0.05 outline-match score of the best frame'), 'R7: topic 11 wording');
            % the defect rule as run_defect_rule applies it (M7 warned and a
            % view under 80 %); the silhouette cap is a caution, not a defect
            tc.verifyTrue(contains(lim, 'A run is defective (the defect rule) when mesh fit (M7) warned and the mesh covers <80 % of some OM view.'), ...
                'Limitations and checks: the defect rule as the code applies it');
            all_help = strjoin(cellfun(@(b) strjoin(b, ' '), {cat.topics.body}, 'UniformOutput', false), ' ');
            tc.verifyEmpty(regexpi(all_help, 'silhouette cap[^.]*defective', 'once'), 'a silhouette-cap run is not called defective');
            v = strjoin(cat.topics(strcmp({cat.topics.id}, 'visualisation')).body, ' ');
            % other Help topics by their titles; the replication guide is
            % not in the repository, so Help never sends a reader to it
            tc.verifyTrue(contains(v, 'with a calibration (Help, "What to supply")'), 'mm: the Help topic What to supply');
            tc.verifyTrue(contains(v, 'Help, "Rhythm and conduction velocity"'), 'the Help topic by its title');
            all_body = strjoin(cellfun(@(b) strjoin(b, ' '), {cat.topics.body}, 'UniformOutput', false), ' ');
            tc.verifyEmpty(regexpi(all_body, 'replication guide|\<guide, section', 'once'), 'no reference to the replication guide');
            titles = {cat.topics.title};
            named = regexp(all_body, 'Help, "([^"]+)"', 'tokens');
            named = cellfun(@(c) c{1}, named, 'UniformOutput', false);
            tc.verifyTrue(all(ismember(named, titles)), sprintf('every Help topic named is a title: %s', strjoin(named, '; ')));
            st = strjoin(cat.topics(strcmp({cat.topics.id}, 'status-and-actions')).body, ' ');
            tc.verifyTrue(contains(st, rabbit_reconstruction_tab.DO_NOT_USE_NEXT), 'Help 7 has the DO NOT USE Next line (W1)');
        end

        function t05_topic_ids_unique(tc)
            % [T05] all topic IDs are unique.
            cat = reconstruction_help_content();
            ids = {cat.topics.id};
            tc.verifyEqual(numel(ids), numel(unique(ids)), ...
                'Topic IDs must be unique');
        end

        function t06_every_topic_has_required_fields(tc)
            % [T06] every topic has id, title, body, citation_keys,
            %        journeys, state_terms fields.
            FIELDS = {'id','title','body','citation_keys','journeys','state_terms'};
            cat = reconstruction_help_content();
            for k = 1:numel(cat.topics)
                t = cat.topics(k);
                for fi = 1:numel(FIELDS)
                    tc.verifyTrue(isfield(t, FIELDS{fi}), ...
                        sprintf('Topic %d missing field %s', k, FIELDS{fi}));
                end
            end
        end

        function t07_body_is_cellstr(tc)
            % [T07] every topic.body is cellstr (non-empty).
            cat = reconstruction_help_content();
            for k = 1:numel(cat.topics)
                t = cat.topics(k);
                tc.verifyTrue(iscellstr(t.body) && ~isempty(t.body), ...
                    sprintf('Topic %d body must be non-empty cellstr', k));
            end
        end

        function t08_citation_keys_are_cellstr(tc)
            % [T08] citation_keys is a cellstr (may be empty).
            cat = reconstruction_help_content();
            for k = 1:numel(cat.topics)
                t = cat.topics(k);
                tc.verifyTrue(iscell(t.citation_keys), ...
                    sprintf('Topic %d citation_keys must be a cell', k));
            end
        end

        function t09_journeys_are_valid(tc)
            % [T09] journeys values are subsets of {'fresh','restore','both'}.
            VALID = {'fresh','restore','both'};
            cat = reconstruction_help_content();
            for k = 1:numel(cat.topics)
                jnys = cat.topics(k).journeys;
                for ji = 1:numel(jnys)
                    tc.verifyTrue(ismember(jnys{ji}, VALID), ...
                        sprintf('Topic %d journey[%d] = ''%s'' invalid', ...
                        k, ji, jnys{ji}));
                end
            end
        end

        function t10_methods_topic_has_required_citation_keys(tc)
            % [T10] methods-and-citations topic carries all 7 required keys
            %        (including membrane-fit).
            REQUIRED_KEYS = {'colmap-sfm','colmap-mvs','apde-mvs', ...
                             'rhythm','laughner','alphashape','membrane-fit'};
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'methods-and-citations');
            tc.verifyTrue(any(idx), 'methods-and-citations topic must exist');
            keys = cat.topics(idx).citation_keys;
            for k = 1:numel(REQUIRED_KEYS)
                tc.verifyTrue(ismember(REQUIRED_KEYS{k}, keys), ...
                    sprintf('methods-and-citations missing required key %s', ...
                    REQUIRED_KEYS{k}));
            end
        end

        function t11_all_static_citation_keys_resolve(tc)
            % [T11] every static citation_key in every topic resolves against
            %        the backend citations() table without a live app.
            %        (Static non-conditional keys only.)
            STATIC_KEYS = {'colmap-sfm','colmap-mvs','apde-mvs', ...
                           'alphashape','membrane-fit','outlier-removal','rhythm','laughner'};
            cat = reconstruction_help_content();

            wt = fileparts(mfilename('fullpath'));
            tab_path = fullfile(wt, '..', 'rabbit_reconstruction_tab.m');
            tc.assumeTrue(isfile(tab_path), ...
                'rabbit_reconstruction_tab.m not found; skip key-resolve check');

            src = fileread(tab_path);
            for k = 1:numel(STATIC_KEYS)
                tc.verifyTrue(contains(src, ["'" STATIC_KEYS{k} "'"]), ...
                    sprintf('Key %s not found in citations() source', ...
                    STATIC_KEYS{k}));
            end

            KNOWN_KEYS = {'colmap-sfm','colmap-mvs','apde-mvs','alphashape','membrane-fit', ...
                'outlier-removal','rhythm','laughner','sam','poisson-2013', ...
                'poisson-2006','icp','umeyama','blender','meshlab', ...
                'colmap-glomap','colmap-vocabtree', ...
                'sift','aliked','lightglue','colmap-rigs','hartley-zisserman', ...
                'gluckman-nayar','sfm-prep','clahe','otsu','koenderink-vandoorn', ...
                'tomasi-kanade','szeliski-kang','loma','laurentini', ...
                'pycamset','zhang','baker-nayar','sauvola','scikit-image', ...
                'padfield','lewis','ericson','filterm'};
            for ti = 1:numel(cat.topics)
                ck = cat.topics(ti).citation_keys;
                for ki = 1:numel(ck)
                    tc.verifyTrue(ismember(ck{ki}, KNOWN_KEYS), ...
                        sprintf('Topic %s key %s unknown', ...
                        cat.topics(ti).id, ck{ki}));
                end
            end
        end
    end

    % =====================================================================
    % UK English copy (Tier-A)
    % =====================================================================
    methods (Test, TestTags = {'TierA', 'Help', 'Copy'})

        function t12_status_and_actions_has_key_terms(tc)
            % [T12] status-and-actions topic contains all key UK-English terms.
            KEY_TERMS = {'RUNNING', 'FAILED', 'PASSED', 'CANCELLED', ...
                         'CANCELLING', 'COMPLETED', 'STATE NOT CONFIRMED', ...
                         'UNVERIFIED RUN RECORD'};
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'status-and-actions');
            tc.verifyTrue(any(idx));
            body = strjoin(cat.topics(idx).body, ' ');
            for k = 1:numel(KEY_TERMS)
                tc.verifyTrue(contains(body, KEY_TERMS{k}), ...
                    sprintf('status-and-actions missing term: %s', KEY_TERMS{k}));
            end
        end

        function t64_viewer_topic_names_all_panels_and_words(tc)
            % [T64] Viewer: all seven panels (conduction velocity too), the
            % Save panel... button, and NOT CURRENT among the empty-panel
            % words, as "Status and what to do" lists it.
            cat = reconstruction_help_content();
            v = cat.topics(strcmp({cat.topics.id}, 'visualisation'));
            body = strjoin(v.body, ' ');
            tc.verifyTrue(contains(body, 'conduction velocity'), 'Viewer must name the CV panel');
            tc.verifyTrue(contains(body, 'NOT CURRENT') && ismember('NOT CURRENT', v.state_terms), ...
                'Viewer must name NOT CURRENT');
            tc.verifyTrue(contains(body, 'Save panel...') && ~contains(body, 'on hover'), ...
                'Viewer must name Save panel..., not a hover button');
        end

        function t13_no_path_disclosure_in_body(tc)
            % [T13] no drive-letter or absolute path appears in any topic body.
            cat = reconstruction_help_content();
            PATH_PATS = {'D:\', 'C:\', '/home/', '/usr/', 'C:/', 'D:/'};
            for ti = 1:numel(cat.topics)
                body = strjoin(cat.topics(ti).body, ' ');
                for p = 1:numel(PATH_PATS)
                    tc.verifyFalse(contains(body, PATH_PATS{p}), ...
                        sprintf('Topic %s body contains path pattern %s', ...
                        cat.topics(ti).id, PATH_PATS{p}));
                end
            end
        end

        function t14_fresh_checklist_has_4_steps(tc)
            % [T14] fresh-checklist body has '1.' through '4.' steps.
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'fresh-checklist');
            body = strjoin(cat.topics(idx).body, ' ');
            for s = 1:4
                tc.verifyTrue(contains(body, [num2str(s) '.']), ...
                    sprintf('fresh-checklist missing step %d.', s));
            end
        end

        function t15_restore_checklist_has_steps(tc)
            % [T15] restore-checklist body has '1.' through '7.' steps.
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'restore-checklist');
            body = strjoin(cat.topics(idx).body, ' ');
            for s = 1:7
                tc.verifyTrue(contains(body, [num2str(s) '.']), ...
                    sprintf('restore-checklist missing step %d.', s));
            end
        end

        function t16_stages_has_8_stages(tc)
            % [T16] stages body names the eight steps of a run on an
            %        existing sparse model, and says how the step numbers
            %        of the progress window are counted instead of numbering
            %        the steps itself (the number depends on the kind of
            %        run).
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'stages');
            body = strjoin(cat.topics(idx).body, ' ');
            names = {'Undistort images (COLMAP)', 'Prepare APDe-MVS scene', 'Dense cloud (APDe-MVS)', ...
                'Depth maps (COLMAP)', 'Dense cloud (COLMAP fusion)', 'Clean cloud and build mesh', ...
                'Check alignment', 'Project optical mapping onto mesh'};
            for s = 1:8
                tc.verifyTrue(contains(body, names{s}), ...
                    sprintf('stages body missing "%s"', names{s}));
            end
            tc.verifyTrue(contains(body, 'the eight steps below'), 'stages body must name the eight steps');
            tc.verifyTrue(contains(body, 'number the steps of the run you see'), ...
                'stages body must say how the progress window numbers the steps');
            tc.verifyFalse(contains(body, 'Step 1 of 8'), 'stages body must not number the steps itself');
        end

        function t17_recon_vs_reprojectfion_distinguishes_both(tc)
            % [T17] reconstruction-vs-reprojection body mentions both
            %        'surface' and 'RHYTHM'.
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'reconstruction-vs-reprojection');
            body = strjoin(cat.topics(idx).body, ' ');
            tc.verifyTrue(contains(body, 'RHYTHM'), ...
                'recon-vs-reprojection must mention RHYTHM');
            tc.verifyTrue(contains(body, 'surface'), ...
                'recon-vs-reprojection must mention surface');
        end

        function t18_copy_on_write_mentions_no_overwrite(tc)
            % [T18] copy-on-write body says tools 'never overwrite'.
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'copy-on-write');
            body = strjoin(cat.topics(idx).body, ' ');
            tc.verifyTrue(contains(body, 'never overwrite'), ...
                'copy-on-write must say tools never overwrite');
        end

        function t19_limitations_mentions_fov_and_calibration(tc)
            % [T19] limitations-and-resources body mentions FOV and calibration.
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'limitations-and-resources');
            body = strjoin(cat.topics(idx).body, ' ');
            tc.verifyTrue(contains(body, 'Field of view', 'IgnoreCase', false), ...
                'limitations must mention Field of view');
            tc.verifyTrue(contains(body, 'alibration', 'IgnoreCase', false), ...
                'limitations must mention calibration');
        end

        function t20_unresolved_citation_message_exact(tc)
            % [T20] UNRESOLVED message text is exact.
            src = probe_contextual_help.read_document_xml();
            tc.assumeTrue(~isempty(src), '.mlapp document.xml not found');
            EXPECTED_MSG = 'Citation unavailable for key ';
            tc.verifyTrue(contains(src, EXPECTED_MSG), ...
                'Resolver UNRESOLVED message not found in .mlapp source');
        end

        function t21_conditional_not_recorded_message_exact(tc)
            % [T21] CONDITIONAL_NOT_RECORDED message text is exact.
            src = probe_contextual_help.read_document_xml();
            tc.assumeTrue(~isempty(src), '.mlapp document.xml not found');
            EXPECTED_MSG = ' - not recorded for this run (the run did not use this method).';
            tc.verifyTrue(contains(src, EXPECTED_MSG), ...
                'Resolver CONDITIONAL_NOT_RECORDED message not found in .mlapp source');
        end
    end

    % =====================================================================
    % Archive integrity (Tier-A)
    % =====================================================================
    methods (Test, TestTags = {'TierA', 'Help', 'Archive'})

        function t22_mlapp_is_valid_zip(tc)
            % [T22] the modified .mlapp is a valid ZIP with testzip OK.
            wt = fileparts(mfilename('fullpath'));
            mlapp = fullfile(wt, '..', 'analyse_optical_mapping.mlapp');
            tc.verifyTrue(isfile(mlapp), '.mlapp not found');
            import java.util.zip.*
            zf = ZipFile(mlapp);
            entries = zf.entries();
            count = 0;
            while entries.hasMoreElements()
                entries.nextElement();
                count = count + 1;
            end
            zf.close();
            tc.verifyEqual(count, 10, 'Modified .mlapp must have 10 ZIP members');
        end

        function t23_mlapp_contains_c32_and_c41(tc)
            % [T23] the app keeps both the stage projection and the Help snapshot.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'reconstruction_stage_projection'), ...
                'C3.2 stage projection is missing from the integrated app');
            tc.verifyTrue(contains(src, 'reconstruction_help_snapshot'), ...
                'The Help snapshot is missing from the integrated app');
        end

        function t24_mlapp_xml_has_no_merge_markers(tc)
            % [T24] the app XML has no unresolved merge markers.
            src = probe_contextual_help.read_document_xml();
            tc.verifyFalse(contains(src, '<<<<<<<'), 'Unresolved merge marker');
            tc.verifyFalse(contains(src, '>>>>>>>'), 'Unresolved merge marker');
        end

        function t25_mlapp_nonxml_members_unchanged(tc)
            % [T25] all non-document.xml members are byte-identical to baseline.
            % appModel.mat and coreProperties.xml change whenever the main app is
            % saved with a code change (the model is re-synced from the code with
            % tests/helpers/mlapp_sync_model.m); re-pin both hashes after each such
            % change, once probe_mlapp_model_consistency passes.
            BASELINE = [ ...
                struct('name', '[Content_Types].xml', ...
                       'sha', 'c99445bf9ec143087e6dcbfe2f349c7f5c279abfc8917525fa456ae6f4c65862'), ...
                struct('name', '_rels/.rels', ...
                       'sha', 'fe8d7e80385c516ef75f8631bb19062f069f7a081608cdb29f901e07e163817e'), ...
                struct('name', 'appdesigner/appModel.mat', ...
                       'sha', '11ceb79fbe80b84e13fbb5d7b8159b2c16f731e2b599fa0c7865e606e9a78c38'), ...
                struct('name', 'metadata/appMetadata.xml', ...
                       'sha', '2e2f858f2a8127e7552841182794392dd783890c43d32b718300af54c3f37162'), ...
                struct('name', 'metadata/coreProperties.xml', ...
                       'sha', '1e62a92439ba3631d3018aabed69c559770aae8841455588124893bcf8593a3f'), ...
                struct('name', 'metadata/mwcoreProperties.xml', ...
                       'sha', 'aca196846a38c0bca9a64b4e8f7bba1b259a0ddf9140d4796687a4f4943af102'), ...
                struct('name', 'metadata/mwcorePropertiesExtension.xml', ...
                       'sha', 'e081cd95fa76b85d0ed50fcffe0631edc5f02f0badc3dc4d09a6e5df53e43bd1'), ...
                struct('name', 'metadata/mwcorePropertiesReleaseInfo.xml', ...
                       'sha', '2655ee3278419cbc718332551040582fc5440ac37f701033a7bcb9e876e2e784'), ...
                struct('name', 'metadata/appScreenshot.png', ...
                       'sha', '861f0cdddca944ebda13fd8bdcbf97fc0e0a033ecc2851e91255f00a46626225')];
            wt = fileparts(mfilename('fullpath'));
            mlapp = fullfile(wt, '..', 'analyse_optical_mapping.mlapp');
            tc.assumeTrue(isfile(mlapp), '.mlapp not found');
            zf = java.util.zip.ZipFile(mlapp);
            for k = 1:numel(BASELINE)
                entry = zf.getEntry(BASELINE(k).name);
                stream = zf.getInputStream(entry);
                bytes = org.apache.commons.io.IOUtils.toByteArray(stream);
                stream.close();
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(bytes);
                hash_bytes = md.digest();
                hex = sprintf('%02x', typecast(hash_bytes, 'uint8'));
                tc.verifyEqual(hex, BASELINE(k).sha, ...
                    sprintf('Non-XML member %s changed', BASELINE(k).name));
            end
            zf.close();
        end

        function t26_mlapp_first_member_is_content_types(tc)
            % [T26] first ZIP member is [Content_Types].xml.
            wt = fileparts(mfilename('fullpath'));
            mlapp = fullfile(wt, '..', 'analyse_optical_mapping.mlapp');
            tc.assumeTrue(isfile(mlapp), '.mlapp not found');
            import java.util.zip.*
            zf = ZipFile(mlapp);
            entries = zf.entries();
            first = entries.nextElement().getName();
            zf.close();
            tc.verifyEqual(char(first), '[Content_Types].xml', ...
                'First ZIP member must be [Content_Types].xml');
        end
    end

    % =====================================================================
    % Source text checks (Tier-A, no app construction)
    % =====================================================================
    methods (Test, TestTags = {'TierA', 'Help', 'Source'})

        function t27_help_menu_declared_in_properties(tc)
            % [T27] ReconstructionHelpMenu property declared.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'ReconstructionHelpMenu'), ...
                'ReconstructionHelpMenu not declared in document.xml');
        end

        function t28_guide_button_declared_in_properties(tc)
            % [T28] ReconstructionGuideButton property declared.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'ReconstructionGuideButton'), ...
                'ReconstructionGuideButton not declared in document.xml');
        end

        function t29_selection_changed_fcn_present(tc)
            % [T29] TabGroup.SelectionChangedFcn wiring present.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'SelectionChangedFcn'), ...
                'SelectionChangedFcn wiring missing in document.xml');
            tc.verifyTrue(contains(src, 'TabGroupSelectionChanged'), ...
                'TabGroupSelectionChanged callback missing');
        end

        function t30_citations_callback_uses_open_help(tc)
            % [T30] ReconstructionCitationsButtonPushed calls reconstruction_open_help.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'reconstruction_open_help'), ...
                'reconstruction_open_help not found in document.xml');
            pattern = 'ReconstructionCitationsButtonPushed';
            idx = strfind(src, pattern);
            tc.verifyFalse(isempty(idx), 'Citations callback not found');
            snippet = src(idx(1) : min(end, idx(1) + 500));
            tc.verifyFalse(contains(snippet, 'ledger_text'), ...
                'Citations callback must not call ledger_text()');
        end

        function t31_close_request_cleans_help_figure(tc)
            % [T31] CloseRequestFcn includes reconstruction_help_figure cleanup.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'reconstruction_help_figure'), ...
                'reconstruction_help_figure not referenced in document.xml');
            tc.verifyTrue(contains(src, 'ObjectBeingDestroyed') && ...
                contains(src, 'obj.reconstruction_close_help()'), ...
                'Deleting the real app must close modeless Help');
        end

        function t32_manifest_restore_calls_maybe_show(tc)
            % [T32] manifest restore path calls reconstruction_maybe_show_first_run.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'reconstruction_maybe_show_first_run'), ...
                'reconstruction_maybe_show_first_run not in document.xml');
        end

        function t33_no_drive_letters_in_product(tc)
            % [T33] no hard-coded drive letters in document.xml or
            %        reconstruction_help_content.m.
            src_xml = probe_contextual_help.read_document_xml();
            src_m   = fileread(fullfile(fileparts(mfilename('fullpath')), ...
                '..', 'reconstruction_help_content.m'));
            PATTERNS = {'D:\', 'C:\', 'D:/', 'C:/'};
            for k = 1:numel(PATTERNS)
                tc.verifyFalse(contains(src_xml, PATTERNS{k}), ...
                    sprintf('document.xml contains drive letter %s', PATTERNS{k}));
                tc.verifyFalse(contains(src_m, PATTERNS{k}), ...
                    sprintf('reconstruction_help_content.m contains drive letter %s', ...
                    PATTERNS{k}));
            end
        end

        function t34_programmatic_depth_property_present(tc)
            % [T34] ReconstructionHelpProgrammaticSelectionDepth transient property present.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'ReconstructionHelpProgrammaticSelectionDepth'), ...
                'ProgrammaticSelectionDepth property missing');
        end

        function t35_pref_adapter_store_property_present(tc)
            % [T35] reconstruction_help_pref_adapter_store property present.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'reconstruction_help_pref_adapter_store'), ...
                'pref_adapter_store property missing');
        end

        function t36_pref_namespace_correct(tc)
            % [T36] preference namespace is analyse_optical_mapping_ReconstructionHelp.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'analyse_optical_mapping_ReconstructionHelp'), ...
                'analyse_optical_mapping_ReconstructionHelp namespace not in document.xml');
        end

        function t37_pref_keys_correct(tc)
            % [T37] both preference keys present with exact names.
            src = probe_contextual_help.read_document_xml();
            tc.verifyTrue(contains(src, 'fresh_checklist_ack_v1'), ...
                'fresh_checklist_ack_v1 preference key missing');
            tc.verifyTrue(contains(src, 'restore_checklist_ack_v1'), ...
                'restore_checklist_ack_v1 preference key missing');
        end

        function t38_no_other_pipeline_named(tc)
            % [T38] the app names no other pipeline: no
            % .m file of the app and no .mlapp holds the word (built from
            % two parts, so that this file does not hold it either)
            word = ['Rec' 'ova'];
            root = fileparts(fileparts(mfilename('fullpath')));
            hits = {};
            files = [dir(fullfile(root, '*.m')); dir(fullfile(root, 'tests', '*.m'))];
            for k = 1:numel(files)
                if contains(fileread(fullfile(files(k).folder, files(k).name)), word, 'IgnoreCase', true)
                    hits{end+1} = files(k).name; %#ok<AGROW>
                end
            end
            apps = dir(fullfile(root, '*.mlapp'));
            for k = 1:numel(apps)
                tmp = tempname; mkdir(tmp);
                unzip(fullfile(root, apps(k).name), tmp);
                x = fullfile(tmp, 'matlab', 'document.xml');
                if exist(x, 'file') == 2 && contains(fileread(x), word, 'IgnoreCase', true)
                    hits{end+1} = apps(k).name; %#ok<AGROW>
                end
                rmdir(tmp, 's');
            end
            tc.verifyEmpty(hits, sprintf('named in: %s', strjoin(hits, ', ')));
        end

        function t39_help_content_file_exists(tc)
            % [T39] reconstruction_help_content.m exists in worktree root.
            wt = fileparts(mfilename('fullpath'));
            f  = fullfile(wt, '..', 'reconstruction_help_content.m');
            tc.verifyTrue(isfile(f), 'reconstruction_help_content.m missing');
        end

        function t40_surgery_helper_exists(tc)
            % [T40] mlapp_surgery.py exists in tests/helpers/.
            wt = fileparts(mfilename('fullpath'));
            f  = fullfile(wt, 'helpers', 'mlapp_surgery.py');
            tc.verifyTrue(isfile(f), 'mlapp_surgery.py missing');
        end
    end

    % =====================================================================
    % Sanitisation (Tier-A)
    % =====================================================================
    methods (Test, TestTags = {'TierA', 'Help', 'Sanitisation'})

        function t41_status_vocabulary_terms_correct(tc)
            % [T41] status-and-actions state_terms matches required vocab.
            REQUIRED = {'RUNNING', 'FAILED', 'MISSING', 'PASSED', ...
                'PASSED WITH WARNINGS', 'CANCELLING', 'CANCELLED', ...
                'COMPLETED', 'COMPLETED - INCONSISTENT', ...
                'READY', 'NOT YET PRODUCED', 'INCOMPATIBLE', ...
                'STATE NOT CONFIRMED', 'UNVERIFIED RUN RECORD', 'INTERRUPTED'};
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'status-and-actions');
            terms = cat.topics(idx).state_terms;
            for k = 1:numel(REQUIRED)
                tc.verifyTrue(ismember(REQUIRED{k}, terms), ...
                    sprintf('status-and-actions state_terms missing: %s', REQUIRED{k}));
            end
        end

        function t42_methods_citations_topic_mentions_conditional(tc)
            % [T42] methods-and-citations body explains, in plain words,
            %        a reference that a run did not record.
            cat = reconstruction_help_content();
            idx = strcmp({cat.topics.id}, 'methods-and-citations');
            body = strjoin(cat.topics(idx).body, ' ');
            tc.verifyTrue(contains(body, 'not recorded for this run'), ...
                'methods-and-citations must explain references not recorded for a run');
        end
    end

    % =====================================================================
    % Earlier probes still present (Tier-A, file check only)
    % =====================================================================
    methods (Test, TestTags = {'TierA', 'Help', 'Regression'})

        function t43_existing_27_probes_present(tc)
            % [T43] the 27 earlier probe files are present.
            EXPECTED = { ...
                'probe_manifest_open_acceptance', 'probe_manifest_moved_run_anomaly', ...
                'probe_manifest_containment', 'probe_restore_and_visualise_gui', ...
                'probe_manifest_mixed_time_stamps', 'probe_manifest_moved_run', ...
                'probe_manifest_partial_runs', 'probe_manifest_ply_payloads', ...
                'probe_manifest_v2_three_artefacts', ...
                'probe_manifest_singleton_collections', 'probe_manifest_open_smoke', ...
                'probe_restore_gui_safety', 'probe_manifest_v1_malformed', ...
                'probe_manifest_v2_shapes', 'probe_restore_camera_activation_sidecar', ...
                'probe_restore_activation_identity', 'probe_reprojection_reference', ...
                'probe_restore_recording_identity', 'probe_reprojection_inputs', ...
                'probe_sidecar_lock_recovery', 'probe_projected_value_rendering', ...
                'probe_sidecar_write_lock', 'probe_projected_zero_assigned', ...
                'probe_restore_records', 'probe_camera_view_restore', ...
                'probe_point_edit_tool_panel', ...
                'probe_visualise_captions'};
            wt = fileparts(mfilename('fullpath'));
            test_dir = wt;
            found = 0;
            for k = 1:numel(EXPECTED)
                p = fullfile(test_dir, [EXPECTED{k} '.m']);
                if isfile(p), found = found + 1; end
            end
            tc.verifyEqual(found, numel(EXPECTED), ...
                sprintf('Only %d of %d expected earlier probes found', ...
                found, numel(EXPECTED)));
        end
    end

    % =====================================================================
    % GUI tests (Tier-B, require display)
    % =====================================================================
    methods (Test, TestTags = {'TierB', 'Help', 'GUI'})

        function t44_help_menu_and_guide_button_exist(tc)
            % [T44] ReconstructionHelpMenu and ReconstructionGuideButton
            %        exist after app construction.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            tc.verifyTrue(isprop(app.recon, 'ReconstructionHelpMenu'), ...
                'ReconstructionHelpMenu property missing');
            tc.verifyTrue(isprop(app.recon, 'ReconstructionGuideButton'), ...
                'ReconstructionGuideButton property missing');
        end

        function t45_help_figure_opens_and_is_modeless(tc)
            % [T45] reconstruction_open_help opens a uifigure that is
            %        non-blocking (figure handle is valid and MATLAB continues).
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.reconstruction_open_help('start-here', 'manual');
            drawnow;
            tc.verifyTrue(~isempty(app.recon.reconstruction_help_figure) && ...
                isvalid(app.recon.reconstruction_help_figure), ...
                'Help figure must be valid after open');
            tc.verifyEqual(app.recon.reconstruction_help_figure.WindowStyle, 'normal', ...
                'Help figure must be normal (modeless)');
        end

        function t46_close_clears_handle(tc)
            % [T46] reconstruction_close_help closes figure and clears handle.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.reconstruction_open_help('start-here', 'manual');
            drawnow;
            app.recon.reconstruction_close_help();
            drawnow;
            tc.verifyTrue(isempty(app.recon.reconstruction_help_figure), ...
                'reconstruction_help_figure must be empty after close');
        end

        function t47_open_twice_does_not_create_second_figure(tc)
            % [T47] calling reconstruction_open_help twice reuses the figure.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.reconstruction_open_help('start-here', 'manual');
            drawnow;
            hf1 = app.recon.reconstruction_help_figure;
            app.recon.reconstruction_open_help('inputs', 'manual');
            drawnow;
            hf2 = app.recon.reconstruction_help_figure;
            tc.verifyEqual(hf1, hf2, ...
                'Reopening Help must reuse the existing figure');
        end

        function t48_pref_injection_missing_key_returns_empty(tc)
            % [T48] injected adapter missing key returns empty.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            val = app.recon.reconstruction_help_pref_get('fresh_checklist_ack_v1');
            tc.verifyTrue(isempty(val), ...
                'Missing preference key must return empty');
        end

        function t49_acknowledge_sets_and_reads_back(tc)
            % [T49] acknowledge writes true and reads back true.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            app.recon.reconstruction_help_acknowledge('fresh', true);
            should = app.recon.reconstruction_help_should_auto_open('fresh');
            tc.verifyFalse(should, ...
                'After acknowledge(true), should_auto_open must return false');
        end

        function t50_close_does_not_acknowledge(tc)
            % [T50] Close button does not write acknowledge.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            app.recon.reconstruction_open_help('fresh-checklist', 'first-run');
            drawnow;
            app.recon.reconstruction_close_help();
            drawnow;
            should = app.recon.reconstruction_help_should_auto_open('fresh');
            tc.verifyTrue(should, ...
                'Close (not Got-it) must not write acknowledge; should_auto_open still true');
        end

        function t51_programmatic_selection_does_not_trigger_help(tc)
            % [T51] programmatic TabGroup selection increment prevents auto-open.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc  = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            app.recon.reconstruction_close_help();
            app.recon.ReconstructionHelpProgrammaticSelectionDepth = uint32(1);
            oc2 = onCleanup(@() probe_contextual_help.safe_reset_depth(app));
            app.recon.TabGroupSelectionChanged(struct());
            drawnow;
            tc.verifyTrue(isempty(app.recon.reconstruction_help_figure) || ...
                ~isvalid(app.recon.reconstruction_help_figure), ...
                'Programmatic selection must not trigger Help auto-open');
        end

        function t52_main_app_close_closes_help_figure(tc)
            % [T52] deleting the main app closes the Help figure.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            app.recon.reconstruction_open_help('start-here', 'manual');
            drawnow;
            hf = app.recon.reconstruction_help_figure;
            tc.verifyTrue(isvalid(hf), 'Help figure must be valid before delete');
            delete(app);
            tc.verifyTrue(~isvalid(hf), 'Help figure must be invalid after app delete');
        end

        function t53_topic_list_contains_all_catalog_topics(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.reconstruction_open_help('start-here', 'manual');
            drawnow;
            cat = reconstruction_help_content();
            tc.verifyEqual(app.recon.reconstruction_help_topic_list.ItemsData, ...
                {cat.topics.id}, 'Topic list must expose all canonical IDs');
        end

        function t54_checklist_checkbox_default_and_semantics(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            app.recon.reconstruction_open_help('fresh-checklist', 'first-run');
            drawnow;
            cb = app.recon.reconstruction_help_show_again_checkbox;
            tc.verifyTrue(isvalid(cb));
            tc.verifyFalse(cb.Value, 'Show-again checkbox must default unchecked');
            app.recon.reconstruction_help_got_it('fresh', true);
            tc.verifyTrue(app.recon.reconstruction_help_should_auto_open('fresh'), ...
                'Checked Show again must persist acknowledgement=false');
        end

        function t55_snapshot_uses_c32_gate_projection(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            snap = app.recon.reconstruction_help_snapshot();
            tc.verifyEqual(snap.status_authority, 'NONE');
            tc.verifyFalse(isempty(snap.gate_projection), ...
                'Snapshot must pass through the current gate projection');
            tc.verifyEqual(numel(snap.checklist_lines), 4);
        end

        function t56_context_resolver_tracks_accordion(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.ReconstructionHelpProgrammaticSelectionDepth = uint32(1);
            app.TabGroup.SelectedTab = app.recon.ReconstructionTab;
            app.recon.reconstruction_help_end_programmatic_selection();
            app.recon.reconstruction_set_accordion(1, false);
            tc.verifyEqual(app.recon.reconstruction_help_topic_for_context(''), 'inputs');
            % Step 2 (Inputs) open: "What to supply", not "Steps of a run"
            app.recon.reconstruction_set_accordion(2, false);
            tc.verifyEqual(app.recon.reconstruction_help_topic_for_context(''), 'inputs');
            app.recon.reconstruction_set_accordion(0, true);
            tc.verifyEqual(app.recon.reconstruction_help_topic_for_context(''), 'copy-on-write');
        end

        function t57_leave_reconstruction_resets_selection_latch(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.ReconstructionHelpFreshShownThisSelection = true;
            tabs = app.TabGroup.Children;
            other = tabs(~arrayfun(@(h) isequal(h, app.recon.ReconstructionTab), tabs));
            tc.assertNotEmpty(other, 'A non-Reconstruction tab is required');
            app.TabGroup.SelectedTab = other(1);
            app.recon.TabGroupSelectionChanged(struct());
            tc.verifyFalse(app.recon.ReconstructionHelpFreshShownThisSelection);
        end

        function t58_runtime_citation_resolution_and_conditions(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            backend = rabbit_reconstruction_tab();
            app.recon.reconstruction_help_citation_adapter_set(backend.citations());
            snap = struct('executed_method_keys', {{'sam'}});
            rec = app.recon.reconstruction_help_resolve_citations( ...
                {'colmap-sfm','sam','not-a-key'}, snap);
            tc.verifyEqual({rec.status}, ...
                {'RESOLVED','CONDITIONAL_EXECUTED','UNRESOLVED'});
            tc.verifyNotEmpty(rec(1).display_reference);
            tc.verifyEqual(rec(3).message, ...
                'Citation unavailable for key not-a-key.');
        end

        function t59_two_instances_observe_last_verified_pref_write(tc)
            probe_contextual_help.skip_if_no_display(tc);
            a = probe_contextual_help.safe_construct(tc);
            b = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete_pair(a, b));
            adapter = probe_contextual_help.make_mem_adapter();
            a.recon.reconstruction_help_pref_adapter_set(adapter);
            b.recon.reconstruction_help_pref_adapter_set(adapter);
            a.recon.reconstruction_help_acknowledge('fresh', true);
            tc.verifyFalse(b.recon.reconstruction_help_should_auto_open('fresh'));
            b.recon.reconstruction_help_acknowledge('fresh', false);
            tc.verifyTrue(a.recon.reconstruction_help_should_auto_open('fresh'));
        end

        function t61_guide_hint_until_checklist_acknowledged(tc)
            % [T61] F18: the Guide button shows a hint and opens the
            %        checklist until it is acknowledged; then plain Guide.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            tc.verifyTrue(app.recon.reconstruction_help_update_hint());
            tc.verifyEqual(app.recon.ReconstructionGuideButton.Text, 'Guide: start here');
            app.recon.ReconstructionGuideButtonPushed();
            drawnow;
            tc.verifyEqual(app.recon.reconstruction_help_topic_list.Value, 'fresh-checklist', ...
                'Guide must open the checklist while it is not acknowledged');
            app.recon.reconstruction_help_got_it('fresh', false);
            tc.verifyEqual(app.recon.ReconstructionGuideButton.Text, 'Guide', ...
                'Got it must remove the hint');
            app.recon.ReconstructionGuideButtonPushed();
            drawnow;
            tc.verifyNotEqual(app.recon.reconstruction_help_topic_list.Value, 'fresh-checklist');
        end

        function t62_tab_visit_does_not_open_help(tc)
            % [T62] F18: a first visit to the tab shows the hint, not the window.
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = probe_contextual_help.make_mem_adapter();
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            app.recon.reconstruction_close_help();
            app.recon.ReconstructionHelpProgrammaticSelectionDepth = uint32(1);
            app.TabGroup.SelectedTab = app.recon.ReconstructionTab;
            app.recon.reconstruction_help_end_programmatic_selection();
            app.recon.ReconstructionHelpFreshShownThisSelection = false;
            app.recon.TabGroupSelectionChanged(struct());
            drawnow;
            tc.verifyTrue(isempty(app.recon.reconstruction_help_figure) || ...
                ~isvalid(app.recon.reconstruction_help_figure), ...
                'A tab visit must not open the Help window');
            tc.verifyEqual(app.recon.ReconstructionGuideButton.Text, 'Guide: start here');
        end

        function t63_topic_change_keeps_the_list(tc)
            % [T63] R3-8: choosing a topic changes the page at once and keeps
            %        the same topic list (it is not rebuilt in its own callback).
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            app.recon.reconstruction_open_help('start-here', 'manual');
            drawnow;
            lst = app.recon.reconstruction_help_topic_list;
            lst.Value = 'inputs';
            app.recon.reconstruction_help_topic_selected(lst);
            drawnow;
            tc.verifyTrue(isvalid(lst) && isequal(app.recon.reconstruction_help_topic_list, lst), ...
                'The topic list must be kept, not rebuilt');
            ttl = findall(app.recon.reconstruction_help_figure, 'Type', 'uilabel', 'FontWeight', 'bold');
            cat = reconstruction_help_content();
            tc.verifyEqual(ttl(1).Text, cat.topics(strcmp({cat.topics.id}, 'inputs')).title, ...
                'One selection must show the chosen topic');
            tc.verifyEqual(numel(ttl), 1, 'Old page parts must be removed');
        end

        function t60_preference_failures_remain_unsuppressed(tc)
            probe_contextual_help.skip_if_no_display(tc);
            app = probe_contextual_help.safe_construct(tc);
            oc = onCleanup(@() probe_contextual_help.safe_delete(app));
            adapter = struct();
            adapter.get = @(~) 'malformed';
            adapter.set = @(~,~) error('probe_contextual_help:InjectedPrefFailure', ...
                'Injected preference write failure.');
            app.recon.reconstruction_help_pref_adapter_set(adapter);
            tc.verifyEmpty(app.recon.reconstruction_help_pref_get( ...
                'fresh_checklist_ack_v1'));
            tc.verifyFalse(app.recon.reconstruction_help_pref_set( ...
                'fresh_checklist_ack_v1', true));
            tc.verifyTrue(app.recon.reconstruction_help_should_auto_open('fresh'), ...
                'Malformed/read-write failures must not suppress onboarding');
        end
    end

    % =====================================================================
    % Helpers (static)
    % =====================================================================
    methods (Static, Access = private)

        function str = read_document_xml()
            % Read matlab/document.xml from the deployed .mlapp, followed by
            % the code of its Reconstruction tab (rabbit_reconstruction_ui.m).
            wt = fileparts(mfilename('fullpath'));
            mlapp = fullfile(wt, '..', 'analyse_optical_mapping.mlapp');
            if ~isfile(mlapp)
                str = '';
                return;
            end
            zf = java.util.zip.ZipFile(mlapp);
            entry = zf.getEntry('matlab/document.xml');
            stream = zf.getInputStream(entry);
            str = char(org.apache.commons.io.IOUtils.toString(stream, 'UTF-8'));
            stream.close();
            zf.close();
            str = [str newline fileread(fullfile(wt, '..', 'rabbit_reconstruction_ui.m'))];
        end

        function skip_if_no_display(tc)
            % Skip Tier-B test when no display is available.
            try
                f = uifigure('Visible','off');
                delete(f);
            catch
                tc.assumeFail('No display available - skipping Tier-B test');
            end
        end

        function app = safe_construct(tc)
            % Construction failures are product failures when Tier-B is active.
            try
                wt = fileparts(mfilename('fullpath'));
                addpath(fullfile(wt, '..'));
                app = analyse_optical_mapping();
            catch e
                tc.assertFail(['App construction failed: ' e.message]);
                app = [];
            end
        end

        function safe_delete(app)
            try
                if ~isempty(app) && isvalid(app)
                    if ~isempty(app.recon.reconstruction_help_figure) && ...
                            isvalid(app.recon.reconstruction_help_figure)
                        delete(app.recon.reconstruction_help_figure);
                    end
                    delete(app);
                end
            catch
            end
        end

        function safe_reset_depth(app)
            try
                if isvalid(app)
                    app.recon.ReconstructionHelpProgrammaticSelectionDepth = uint32(0);
                end
            catch
            end
        end

        function safe_delete_pair(a, b)
            probe_contextual_help.safe_delete(a);
            probe_contextual_help.safe_delete(b);
        end

        function adapter = make_mem_adapter()
            m = containers.Map('KeyType', 'char', 'ValueType', 'any');
            adapter = struct();
            adapter.get = @(k) probe_contextual_help.map_get(m, k);
            adapter.set = @(k, v) probe_contextual_help.map_set(m, k, v);
        end

        function val = map_get(m, key)
            k = char(key);
            if isKey(m, k)
                val = m(k);
            else
                val = [];
            end
        end

        function map_set(m, key, val)
            k = char(key);
            m(k) = val; %#ok<NASGU>
        end
    end
end
