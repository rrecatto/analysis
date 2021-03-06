classdef trode
    properties 
        trodeName
        chans
        detectParams
        sortingParams
        
        units
        
        spikeEvents
        spikeWaveForms
        spikeTimeStamps
        spikeAssignedCluster
        spikeRankedCluster
        waveformsToCluster  % ## to make it easier to plot clusters across all channels.
        clusteredSpikes
        spikeModel          % ## added these two for interactivity with gui
        
        Mean
        Std
    end
    
    properties (Constant = true)
        maxAllowableSamplingRateDeviation = 10^-7;
    end
    
    properties (Transient=true)
        NeuralData = [];
        NeuralDataTimes = [];
    end
    
    methods
        %% constructor
        function tr = trode(chans)
            % ## not sure this is correct error check - assert(isnumeric(chans),'chans is not a numeric array')
            tr.chans = chans;
            % this stuff is hard coded. but thats okay.
            tr.detectParams = filteredThreshold('StandardFiteredThresh_7__14_2015',repmat(5,1,length(chans)),'std');
            
            % set standard sorting params here
            tr.sortingParams = KlustaKwik('KlustaKwikStandard'); % ## StandardKlustaKwik           
        end %trode  
        
        %% spike detection and sorting
        function [tr, warn] = detectSpikes(tr,dataPath, session)
            tr.NeuralData = [];
            tr.NeuralDataTimes = [];
            tr.Mean = [];
            tr.Std = [];
            warn.flag = -1;
            for i = 1:length(tr.chans)
                a = dir(fullfile(dataPath,sprintf('100_CH%d.continuous',tr.chans(i)))); %makes sure to process only 100_CH files
                if length(a)>1
                    error('too many records');
                else
                    [rawData, rawTimestamps, ~, dataMean, dataStd] =load_open_ephys_data([dataPath,'\',a.name]);
                    if any(((diff(rawTimestamps)-mean(diff(rawTimestamps)))/mean(diff(rawTimestamps)))> tr.maxAllowableSamplingRateDeviation)
                        warning('bad timestamps! why?');  %weird timestamp bug, stores in messages if bug occurs
                        warn.flag=1;
                        warn.identifier = 'trode.detectSpikes';
                        warn.message = 'bad timestamps! why?';
                        warn.ind = find(((diff(rawTimestamps)-mean(diff(rawTimestamps)))/mean(diff(rawTimestamps)))> tr.maxAllowableSamplingRateDeviation);
                        for i = 1:length(warn.ind)
                            if i == 1
                                warn.data = [rawTimestamps(warn.ind(i)) rawTimestamps(warn.ind(i)+1)];
                            else
                                warn.data = [warn.data;rawTimestamps(warn.ind(i)) rawTimestamps(warn.ind(i)+1)];
                            end
                        end
                    end
                    tr.NeuralData = [tr.NeuralData rawData];  %stores raw data for now
                    tr.NeuralDataTimes = rawTimestamps;
                    tr.Mean = [tr.Mean dataMean];
                    tr.Std = [tr.Std dataStd];
                end
            end
            
            % once we have raw data we detect the spikes from it
            [tr.spikeEvents, tr.spikeWaveForms, tr.spikeTimeStamps, tr.detectParams]= ...
                tr.detectParams.detectSpikesFromNeuralData(tr.NeuralData, tr.NeuralDataTimes);
            
            tr.NeuralData = [];   %empties raw data, no need to store any longer
            tr.NeuralDataTimes = [];
        end
        
        % does preliminary spike grouping to prepare for manual grouping.
        function tr = sortSpikes(tr)
            tr.spikeAssignedCluster = [];
            tr.spikeRankedCluster = [];
            
            [tr.spikeAssignedCluster, tr.spikeRankedCluster, tr.sortingParams, tr.spikeModel] = tr.sortingParams.sortSpikesDetected( ...
                reshape(tr.spikeWaveForms,tr.numSpikes,tr.numSampsPerSpike*length(tr.chans)), tr.spikeTimeStamps);           
        end
        
        % calls GUI on trode to further group clusters
        function newTr = inspectSpikes(tr)
            newTr = interactiveInspectGUI(tr);
        end
        
        function tr = addUnit(tr,unit)
            disp('adding Unit');
            if isa(unit,'singleUnit')
                if tr.numUnits ==0
                    tr.units = unit;
                else
                    tr.units(end+1) = unit;
                end
            end
        end
        
        %% helpers
        function out = numSpikes(tr)
            out = size(tr.spikeEvents,1);
        end
        
        function out = numSampsPerSpike(tr)
            out = size(tr.spikeWaveForms,2);
        end
        
        function out = numUnits(tr)
            if ~isempty(tr.units)
                out = length(tr.units);
            else
                out = 0;
            end
        end    
        
        function out = getReport(tr)
            numUnits = tr.numUnits();
            out = struct;
            for i = 1:numUnits
                out.unitDetails{i} = tr.units(i).getReport();
                for j = 1:i
                    out.crossCorrDetails{i,j}.unitIDs = [i,j];
                    [out.crossCorrDetails{i,j}.xcorr, ...
                        out.crossCorrDetails{i,j}.shuffleMean,...
                        out.crossCorrDetails{i,j}.shuffleSTD] = xcorr(tr.units(i),tr.units(j));
                end
            end
        end

    end
end