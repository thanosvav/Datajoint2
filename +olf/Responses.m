%{
-> reso.FluorescenceTrace
-> olf.RespOpt
---
resp_on                    : mediumblob                    # on response matrix [stimuli trials]
resp_off                   : mediumblob                    # off response matrix [stimuli trials]
stimuli                     : mediumblob                    # stimuli
%}


classdef Responses < dj.Computed
    
    properties
         keySource = (reso.FluorescenceTrace*olf.RespOpt('process = "yes"') & olf.Sync)
    end
    
    methods(Access=protected)
        
        function makeTuples(obj,key)
            
            % fetch stuff
            trace = double(fetch1(reso.FluorescenceTrace & key,'trace'));
            fps = fetch1(reso.ScanInfo & key,'fps');
            stimTrials = fetch1(olf.Sync & key,'trials');
            [trials, stims] = fetchn( olf.StimPeriods & (olf.Sync & key),'trial','stimulus');
            [on,off,base, on_delay, off_delay] = fetchn(olf.RespOpt & key,...
                'response_period','off_response_period','baseline_period','response_delay','off_response_delay');
            
            % process traces
            hp = 0.02; 
            trace = trace + abs(min(trace(:)))+eps;
            trace = trace./ne7.dsp.convmirr(trace,hamming(round(fps/hp)*2+1)/sum(hamming(round(fps/hp)*2+1)))-1;  %  dF/F where F is low pass
            trace = trace - prctile(trace,10);

            % compute stimuli
            ustims = unique(stimTrials);
            mxtrial = max(ustims([1 diff(ustims)]==1));
            if mxtrial<0.8*length(stims)
                disp('Too many trials missing!')
            end
            stims = stims(1:mxtrial);
            trials = trials(1:mxtrial);
            uniStims = unique(stims);
            
            % calculate responses
            R_ON = [];
            R_OFF = [];
            for iuni = 1:length(uniStims)
                stim = uniStims(iuni);
                uni_trials = trials(strcmp(stims,stim));
                for itrial = 1:length(uni_trials)
                    tstart = find(stimTrials == uni_trials(itrial),1,'first');
                    tend = find(stimTrials == uni_trials(itrial),1,'last')+1;
                    if tend+round(fps*(off+off_delay)/1000)-1 > length(trace)
                        break
                    end
                    if base
                        ON_base = mean(trace(max([tstart-round(fps*base/1000) 1]):tstart-1));
%                        OFF_base = mean(trace(max([tend-round(fps*base/1000) 1]):tend-1));
                         OFF_base = ON_base;
                    else
                        ON_base = 0 ;
                        OFF_base = 0 ;
                    end
                    R_ON{iuni,itrial} = mean(trace(tstart:tstart+round(fps*(on+on_delay)/1000)-1)) - ON_base;
                    R_OFF{iuni,itrial} = mean(trace(tend:tend+round(fps*(off+off_delay)/1000)-1)) - OFF_base;
                end
            end
            
            % remove incomplete trials
            index = ~any(cellfun(@isempty,R_ON));
            
            % insert
            tuple = key;
            tuple.resp_on = cell2mat(R_ON(:,index));
            tuple.resp_off = cell2mat(R_OFF(:,index));
            tuple.stimuli = uniStims;
            insert( obj, tuple );
            
        end
    end
    
    methods (Static)
        function trace = dfof(trace,fps)
            hp = 0.02; 
            trace = trace + abs(min(trace(:)))+eps;
            trace = trace./ne7.dsp.convmirr(trace,hamming(round(fps/hp)*2+1)/sum(hamming(round(fps/hp)*2+1)))-1;  %  dF/F where F is low pass
            trace = trace - prctile(trace,10); 
        end
    end
end