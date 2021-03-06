%{
mov3d.RFFilter (computed) # population RF
-> preprocess.Sync
-> preprocess.SpikeMethod
-> preprocess.Method
-> mov3d.RFFilterOpt
---
map                    : longblob        # standard deviation from center of population RF
rf_idx                 : longblob        # index of subbins with stimulus in pop RF (trials)(subbins)
rf_trials              : longblob        # trial index (trial indexes)
v1_rfs                 : longblob        # Individual RF centers [x y]
%}

classdef RFFilter < dj.Relvar & dj.AutoPopulate
    
    properties
        popRel  = (experiment.Scan  ...
            * (preprocess.Spikes & 'spike_method = 5'  & 'extract_method=2'))...
            * (mov3d.RFFilterOpt & 'process = "yes"') ...
            * (preprocess.Sync  & (vis.MovieClipCond * vis.Trial & ...
            ((vis.Movie & 'movie_class="object3d"') | (vis.Movie & 'movie_class="multiobjects"')) & ...
            'trial_idx between first_trial and last_trial')) ...
            & (tuning.MonetFit | tuning.DotRFMapPop )
    end
    
    methods(Access=protected)
        
        function makeTuples(self, key)
            
            tuple = key;
            
            % params
            [binsize, rf_thr] = fetch1(mov3d.RFFilterOpt & key,'binsize','rf_thr');
            
            % if exists(self & tuple); return;end
            monet_tuple = tuning.MonetFit & key;
            
            % get V1 RFs
            sesskey = rmfield(key,'scan_idx');
            V1key = fetch(experiment.Scan & 'brain_area= "V1"' & sesskey);
            if isempty(V1key)
                sesskey.session = sesskey.session-1;
                V1key = fetch(experiment.Scan & 'brain_area= "V1"' & sesskey);
            end
            if  monet_tuple.count > 0
                [xloc, yloc] = fetchn(tuning.MonetFit & V1key(1),'x','y');  % degrees from center
            else
                [xloc, yloc] = fetchn(tuning.DotRFMap & V1key(1),'center_x','center_y');  % fraction of x from center
            end
            
            if isempty(xloc); warning('No RFs found!');return;end
            
            % convert to pixels from center
            sess = fetch(preprocess.Sync*vis.Session & key,'resolution_x','resolution_y','monitor_distance','monitor_size');
            rect = [sess.resolution_x sess.resolution_y];
            degPerPix = 180/pi*sess.monitor_size*2.54/norm(rect(1:2))/sess.monitor_distance;
            if  monet_tuple.count > 0
                xloc = xloc/degPerPix;
                yloc = yloc/degPerPix;
            else
                xloc = xloc * rect(1);
                yloc = yloc * rect(1);
            end
            
            % fit RFs
            m = fitgmdist([xloc,yloc],1);
            
            % create rf boundary
            [x,y] = meshgrid((1:rect(1))-rect(1)/2,(1:rect(2))-rect(2)/2);
            X=[x(:) y(:)];
            X = bsxfun(@minus, X, m.mu);
            d = sum((X /m.Sigma) .* X, 2);
            pop_rf = reshape(d,rect(2),rect(1)); % in pixel space
            
            % stimulus_trial_xy_position
            [paramsObj,obj,fps] = fetchn(vis.Movie & (vis.MovieClipCond & key),...
                'params','movie_name','frame_rate');
            
            stim_idx = [];
            for iobj = 1:length(obj)
                params = paramsObj{iobj};
                frameStep = fps(iobj)*binsize/1000; % in frames
                if isfield(params,'frames')
                    frameIdx = 1:frameStep:params.frames(end);
                    px = interpn(params.frames,params.camera_pos_x,frameIdx,'cubic');
                    pz = interpn(params.frames,params.camera_pos_z,frameIdx,'cubic');
                else  % handle multiobject param file
                    frameIdx = 1:frameStep:params.frame_id(end);
                    px = [];pz =[];
                    if isfield(params,'Object01_y')
                        px(:,end+1) = -interpn(params.frame_id,params.Object01_y,frameIdx,'cubic');
                        pz(:,end+1) = interpn(params.frame_id,params.Object01_z,frameIdx,'cubic');
                    end
                    if isfield(params,'Object02_y')
                        px(:,end+1) = -interpn(params.frame_id,params.Object02_y,frameIdx,'cubic');
                        pz(:,end+1) = interpn(params.frame_id,params.Object02_z,frameIdx,'cubic');
                    end
                    if isfield(params,'Object03_y')
                        px(:,end+1) = -interpn(params.frame_id,params.Object03_y,frameIdx,'cubic');
                        pz(:,end+1) = interpn(params.frame_id,params.Object03_z,frameIdx,'cubic');
                    end
                end
                nx = round(normalize(px)*rect(1));
                nz = round(normalize(pz)*rect(2));
                nx(nx==0) = 1;nz(nz==0) = 1;
                % stimulus_bin_xy_position inside circle
                stim_idx{iobj} = any(pop_rf(sub2ind(size(pop_rf),nz,nx))<rf_thr,2);
            end
            
            % get trials
            trials = pro(preprocess.Sync*vis.Trial & (experiment.Scan & key) & 'trial_idx between first_trial and last_trial', 'cond_idx', 'flip_times');
            trials = fetch(trials*vis.MovieClipCond, '*', 'ORDER BY trial_idx'); %fetch(trials*psy.Movie, '*', 'ORDER BY trial_idx') 2016-08
            
            % find bins within the pop RF
            rf_idx = []; rf_trials = [];
            for itrial = 1:length(trials)
                rf_trials(itrial) = trials(itrial).trial_idx;
                obj_idx = strcmp(obj,trials(itrial).movie_name);
                frames_per_trial = trials(itrial).cut_after*fps(obj_idx);
                start = (trials(itrial).clip_number - 1)*frames_per_trial;
                rf_idx{itrial} = stim_idx{obj_idx}(find(frameIdx>start,1,'first') : ...
                    find(frameIdx<(start+frames_per_trial),1,'last'));
            end
            
            % populate
            tuple.map = pop_rf;
            tuple.rf_idx = rf_idx;
            tuple.rf_trials = rf_trials;
            tuple.v1_rfs = [xloc yloc];
            self.insert(tuple)
        end
    end
    
end
