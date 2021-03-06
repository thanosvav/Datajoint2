%{
mov3d.DecodeTime (computed) # calcium trace
-> preprocess.Sync
-> mov3d.DecodeOpt
-> preprocess.SpikeMethod
-> preprocess.Method
---
obj_cis                      : longblob                      # classification performance for trials that follow same object
obj_trans                    : longblob                      # classification performance for trials that follow opposite object
%}

classdef DecodeTime < dj.Relvar & dj.AutoPopulate
    %#ok<*AGROW>
    %#ok<*INUSL>
    
    properties
        popRel  = (experiment.Scan  ...
            * (preprocess.Spikes & 'spike_method = 5'  & 'extract_method=2'))...
            * (mov3d.DecodeTimeOpt & 'process = "yes"') ...
            * (preprocess.Sync & (vis.MovieClipCond & (vis.Movie & 'movie_class="object3d"')))
    end
    
    methods(Access=protected)
        
        function makeTuples(self, key)
            
            tuple = key;
            
            [dec_method,trial_bins,trial_method] = ...
                fetch1(mov3d.DecodeTimeOpt & key,...
                'decode_method','trial_bins','trial_method');
            
            [Data, Trials] = getData(self,key); % [Cells, Obj, Trials]
            
            % create trial index
            trial_idx = 1:size(Data,3);
            switch trial_method
                case 'random'
                    data_idx = randperm(size(Data,3));
                case 'sequential'
                    data_idx = 1:size(Data,3);
            end
            trial_bin = floor(size(Data,3)/trial_bins);
            minBinNum = mode(diff(find(abs(diff(reshape(Trials',[],1)))>0)));
            obj_cis = cell(trial_bins,1);
            obj_trans = cell(trial_bins,1);
            % run the decoding
            
            parfor itrial = 1:trial_bins
                
                display(['Decoding trial # ' num2str(itrial)])
                tIdx = 1+trial_bin*(itrial-1):trial_bin*itrial;
                data = Data(:,:,data_idx(tIdx));
                trials = Trials(:,trial_idx(tIdx));
                
                mi = nan(size(data,2),size(data,3));
                if strcmp(dec_method,'nnclassSV')
                    % mi = eval([dec_method '(data,''trials'',1)']);
                    mi = nnclassSV(data,'trials',1);
                end
                utrials = unique(trials(:));
                
                cis = [];
                trans = [];
                for iseg = 2:length(utrials)
                    idx = find(trials==utrials(iseg));
                    [x,~] = ind2sub(size(trials),idx);
                    [xbef,~] = ind2sub(size(trials),find(trials==utrials(iseg-1)));
                    if all(xbef(end)==x)
                        cis{end+1} = mi(idx);
                    elseif all(xbef(end)~=x)
                        trans{end+1} = mi(idx);
                    end
                end
                idx = cellfun(@(x) length(x)==minBinNum,cis);
                obj_cis{itrial} = mean(cell2mat(cis(idx)),2);
                idx = cellfun(@(x) length(x)==minBinNum,trans);
                obj_trans{itrial} = mean(cell2mat(trans(idx)),2);
            end
            
            % insert
            tuple.obj_cis = obj_cis;
            tuple.obj_trans = obj_trans;
            
            % correct for key mismach
%             tuple = rmfield(tuple,'spike_method');
%             tuple = rmfield(tuple,'extract_method');
%             tuple.spike_inference = key.spike_method;
%             tuple.segment_method = key.extract_method;
            self.insert(tuple)
        end
    end
    
    methods
        function [Data, Trials] = getData(obj,key,ibin)
            
            bin = fetch1(mov3d.DecodeTimeOpt & key, 'binsize');
            if nargin>2;bin = ibin;end
                      
            [Traces, caTimes] = pipetools.getAdjustedSpikes(key);
            xm = min([length(caTimes) size(Traces,1)]);
            X = @(t) interp1(caTimes(1:xm)-caTimes(1), Traces(1:xm,:), t, 'linear', nan);  % traces indexed by time
            
            trials = pro(preprocess.Sync*vis.Trial & (experiment.Scan & key) & 'trial_idx between first_trial and last_trial', 'cond_idx', 'flip_times');
            trials = fetch(trials*vis.MovieClipCond, '*', 'ORDER BY trial_idx'); %fetch(trials*psy.Movie, '*', 'ORDER BY trial_idx') 2016-08
            
            snippet = []; % traces: {object,trials}(subbin,cells)
            stims = [2 1];
            idx = 0;
            trial_idx = [];
            for trial = trials'
                idx = idx+1;
                stim = stims(~isempty(strfind(trial.movie_name,'obj1'))+1); % stims(~isempty(strfind(trial.path_template,'obj1'))+1); 2016-08
                % extract relevant trace & bin
                fps = 1/median(diff(trial.flip_times));
                t = trial.flip_times - caTimes(1);
                d = max(1,round(bin/1000*fps));
                trace = convn(X(t),ones(d,1)/d,'same');
                trace = trace(1:d:end,:);
                snippet{stim,idx} = trace;
                trial_idx{stim,idx} = repmat(trial.trial_idx,size(trace,1),1);
            end
            
            A = snippet(1,:);
            A_trials = trial_idx(1,:);
            idx = ~cellfun(@isempty,A);
            A = A(idx);
            A_trials = A_trials(idx);
            objA = permute(reshape(cell2mat(cellfun(@(x) reshape(x',[],1),A,'uni',0)'),size(A{1},2),[]),[3 1 2]);
            objA_trials = permute(reshape(cell2mat(cellfun(@(x) reshape(x',[],1),A_trials,'uni',0)'),size(A_trials{1},2),[]),[3 1 2]);
            
            B = snippet(2,:);
            B_trials = trial_idx(2,:);
            idx = ~cellfun(@isempty,B);
            B = B(idx);
            B_trials = B_trials(idx);
            objB = permute(reshape(cell2mat(cellfun(@(x) reshape(x',[],1),B,'uni',0)'),size(B{1},2),[]),[3 1 2]);
            objB_trials = permute(reshape(cell2mat(cellfun(@(x) reshape(x',[],1),B_trials,'uni',0)'),size(B_trials{1},2),[]),[3 1 2]);
            
            
            % Arrange data
            mS = min([size(objA,3) size(objB,3)]);
            Data = reshape(permute(objA(:,:,1:mS),[2 4 3 1]),size(objA,2),1,[]);
            Data(:,2,:) = reshape(permute(objB(:,:,1:mS),[2 4 3 1]),size(objB,2),1,[]);
            Trials = reshape(permute(objA_trials(:,:,1:mS),[2 4 3 1]),size(objA_trials,2),1,[]);
            Trials(:,2,:) = reshape(permute(objB_trials(:,:,1:mS),[2 4 3 1]),size(objB_trials,2),1,[]);
            Trials = squeeze(Trials(1,:,:));
        end
        
        function plot(obj,k)
            if nargin<2
                keys = fetch(obj);
            else
                keys = fetch(obj & k);
            end
            for k = keys'
                bin = fetch1(mov3d.DecodeTimeOpt & k,'binsize');
                obj_cis = fetch1(mov3d.DecodeTime & k,'obj_cis');
                obj_trans = fetch1(mov3d.DecodeTime & k,'obj_trans');
                idx = ~cellfun(@isempty,obj_cis);
                cis = cell2mat(obj_cis(idx)');
                idx = ~cellfun(@isempty,obj_trans);
                trans = cell2mat(obj_trans(idx)');
                clf
                errorPlot(1:size(cis,1),cis','errorColor',[0 0 0.5'])
                hold on
                errorPlot(1:size(cis,1),trans','errorColor',[0.5 0 0])
                ylim([0.5 1])
                set(gca, 'xtick',1:size(cis,1),'xticklabel',bin/1000:bin/1000:5)
                try
                    r = nanmean(reshape(fetch1(mov3d.Repeats & k & 'rep_opt = 4','r'),[],1));
                catch
                    r = 0;
                end
                title(sprintf('animal:%d session:%d scan:%d area:%s dec_opt:%d r:%.2f',...
                    k.animal_id,k.session,k.scan_idx,...
                    fetch1(experiment.Scan & k,'brain_area'),k.dec_opt,r))
                pause
            end
        end
        
        function plotArea(obj,k,thr)
            process = @(x) cellfun(@(y) mean(cell2mat(y(~cellfun(@isempty,y))'),2),x,'uni',0);
            if nargin<2 || isempty(k)
                keys = fetch(obj);
            else
                keys = fetch(obj & k);
            end
            areas = fetchn(experiment.Scan & keys,'brain_area');
            bin = unique(fetchn(mov3d.DecodeTimeOpt & keys,'binsize'));
            dec_opt = unique(fetchn(mov3d.DecodeTimeOpt & keys,'dec_opt'));
            for area = unique(areas)'
                if nargin>2 && thr>0
                    [obj_cis, obj_trans, r] = ...
                        fetchn(mov3d.DecodeTime * (mov3d.Repeats & 'rep_opt = 4') & keys(strcmp(areas,area)),...
                        'obj_cis','obj_trans','r');
                    cis = cell2mat(process(obj_cis(cellfun(@(x) nanmean(x(:))>thr, r)))');
                    trans = cell2mat(process(obj_trans(cellfun(@(x) nanmean(x(:))>thr, r)))');
                else
                   [obj_cis, obj_trans] = ...
                        fetchn(mov3d.DecodeTime& keys(strcmp(areas,area)),...
                        'obj_cis','obj_trans');
                    cis = cell2mat(process(obj_cis)');
                    trans = cell2mat(process(obj_trans)');
                end
                figure
                errorPlot(1:size(cis,1),cis','errorColor',[0 0 0.5'])
                errorPlot(1:size(cis,1),trans','errorColor',[0.5 0 0])
                ylim([0.5 1])
                set(gca, 'xtick',1:size(cis,1),'xticklabel',bin/1000:bin/1000:5)
                title(sprintf('area:%s dec_opt:%d',area{1},dec_opt))
            end
        end
    end
    
end
