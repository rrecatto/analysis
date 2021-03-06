classdef Session
    properties
        sessionID % rip From Folder
        timeStamp % get automatically
        
        subject   
        electrode % grouping of electrodes. (single or multi-channel).
        monitor   % all 3 of these object in the 'hardware' folder
        rig
        trials
        
        sessionPath   
        sessionFolder  
        trialDataPath 
        
        trodes
        eventData
                
        history       = {};
    end
    methods
        function sess = Session(subject,sessionPath,sessionFolder,trialDataPath, etrode, mon, rigState)
            assert(ischar(subject),'subject input is not a character')
            sess.subject = subject;
                        
            sess.timeStamp = now;
            
            assert((exist(sessionPath,'dir')==7),'No Access to sessionPath or not correct path');
            sess.sessionPath = sessionPath;
            
            assert((exist(fullfile(sessionPath,sessionFolder),'dir')==7),'No Access to sessionFolder or not correct path');
            sess.sessionFolder = sessionFolder;
            
            assert((exist(trialDataPath,'dir')==7),'No Access to trialDataPath or not Correct path');
            sess.trialDataPath = trialDataPath;
            
            assert(isa(etrode,'electrode'),'etrode is not an electrode');
            sess.electrode = etrode;
            
            assert(isa(mon,'monitor'),'mon is not a monitor');
            sess.monitor = mon;
 
            assert(isa(rigState,'rig'),'rigStat is not a rig');
            sess.rig = rigState;
            
            sess.sessionID = sprintf('%s_%s',upper(subject),datestr(sess.timeStamp,30));
            sess.history{end+1} = sprintf('Initialized session @ %s',datestr(sess.timeStamp,21));
        end
        
        
        % detects and sorts spikes, as well as gets event data for a
        % session. The root method call.
        function session = process(session, mappings) 
            
            currDir = pwd; 
            
            % 1. get events data (##pass in correct file)
            session.eventData = eventData(session.trialDataPath, mappings);
            
            % 2. get the trodes for the electrode
            session.trodes = session.electrode.getPotentialTrodes(session.sessionPath,session.sessionFolder);
            
            % 3. detect spikes
            try
                disp('Detecting Spikes ... ');
                session = session.detectSpikes();
            catch ex
                session = session.addToHistory('Error',ex);
                fName = saveSession(session);
                %keyboard
            end
            
            %saves session just in case failure before sorting occurs
            fName = saveSession(session);
            
            % 4. sort spikes
            try
                disp('Sorting Spikes ... ');
                session = session.sortSpikes();
            catch ex
                session = session.addToHistory('Error',ex);
                fName = saveSession(session);
            end
        end      
        
        % takes raw neural data and goes through it in order to detect
        % spikes.
        function session = detectSpikes(session)
            for i = 1:length(session.trodes)
                dataPath = fullfile(session.sessionPath,session.sessionFolder); %finds corresponding .continuous file
                try
                    [session.trodes(i), warn] = session.trodes(i).detectSpikes(dataPath, session); %detects spikes
                    det.identifier = ['Session.detectSpikes ' ,datestr(now)];          
                    det.message = sprintf('detected on trode %d of %d',i, length(session.trodes));
                    session = session.addToHistory('Completed',det);
                
                    if warn.flag==1 % if bad timestamps found while detecting
                        det.identifier = ['BAD_TIMESTAMPS'];
                        det.message = warn;
                        session = session.addToHistory('Completed',det); %saves any bad timestamps to history
                    end
                    
                    fName = saveSession(session); %save after each trode in case failure
                catch ex
                    session = session.addToHistory('Error',ex);
                    fName = saveSession(session);
                end
            end
        end

        % once spikes detected, using klustakwik algorithm to sort spikes
        function session = sortSpikes(session)
            for i = 1:length(session.trodes)
                try
                    session.trodes(i) = session.trodes(i).sortSpikes();
                    det.identifier = ['Session.sortSpikes ', datestr(now)];
                    det.message = sprintf('sorted on trode %d of %d',i, length(session.trodes));
                    session = session.addToHistory('Completed',det);
                    fName = saveSession(session);          %saves session between each sort just in case fails.
                catch ex
                    session = session.addToHistory('Error',ex);
                    fName = saveSession(session);
                end
            end
        end
        
        % once spikes sorted, use inspect spikes to pull up GUI to further
        % cluster the spikes.
        function session = inspectSpikes(session,k)
            for i = k:length(session.trodes)
                try
                    session.trodes(i) = session.trodes(i).inspectSpikes();
                    det.identifier = ['Session.inspectSpikes ', datestr(now)];
                    det.message = sprintf('inspected on trode %d of %d',i, length(session.trodes));
                    session = session.addToHistory('Completed',det);
                    disp('Saving Session. . .');
                    fName = saveSessionGUI(session);          %saves session between each sort just in case fails.
                catch ex
                    session = session.addToHistory('Error',ex);
                    fName = saveSessionGUI(session);
                end
            end
        end
        
        % gets smallest trial number
        function minTrial = getMinTrial(sess)
            if length(sess.eventData.messages) == 1 % cases where we dont have Messages Events
                minTrial = Nan; 
            else
                minTrial = sess.eventData.messages(1).trial;    
            end
        end
        
        % gets largest trial number
        function maxTrial = getMaxTrial(sess)
            if length(sess.eventData.messages) == 1 % cases where we dont have Messages Events
                maxTrial = Nan;
            else
                maxTrial = sess.eventData.messages(end).trial;
            end            
        end
        
        % gets start and end index for a trial
        function [startInd,stopInd] = getTrialIndexRange(sess, trial) 
            [startTime, endTime] =  getTrialStartStopTime(sess, trial); 
            samplingFreq = sess.trodes(1).detectParams.samplingFreq;
            
            startInd = startTime*samplingFreq;
            stopInd = endTime*samplingFreq;
        end
        
        % gets start and end time for a trial
        function [startTime, endTime] =  getTrialStartStopTime(sess, trial)
            if trial > getMaxTrial(sess) || trial < getMinTrial(sess)
                error('ERROR: trial out of range of session');
            end
            ind = (trial - getMinTrial(sess)) + 1; %% Assumes that trials increase 1 at a time.
            
            if sess.eventData.trials(ind).trialNumber ~= trial
                warning('Possibly not displaying start/stop of correct trial');
                disp('Passed in trial:');
                disp(trial);
                disp('However startTime, endTime are of trial');
                disp(sess.eventData.trials(ind).trialNumber);
            end

            startTime = sess.eventData.trials(ind).start;
            endTime = sess.eventData.trials(ind).stop;
        end
        
        % gets all the events for a passed in trial
        function trialEvents = getTrialEvents(sess, trial)
            [startTime, endTime] =  getTrialStartStopTime(sess, trial);
            
            eData = sess.eventData.out;
            for i = 1:length(eData)
                ind = (eData(i).eventTimes <= endTime & eData(i).eventTimes >= startTime);
                trialEvents(i).channelNum = eData(i).channelNum;
                trialEvents(i).eventTimes = eData(i).eventTimes(ind);
                trialEvents(i).eventID = eData(i).eventID(ind);
                trialEvents(i).eventType = eData(i).eventType(ind);
                trialEvents(i).sampNum = eData(i).sampNum(ind);
            end
        end
        
        % plots the events for a passed in trial
        function success = plotTrialEvents(sess, trial)
            success = true;
            samplingFreq = sess.trodes(1).detectParams.samplingFreq;
            
            [start,stop] = getTrialIndexRange(sess, trial);

            xAxis = (start-1000:stop+1000);
            numChans = length(sess.eventData.out);
            
            trialEvents = getTrialEvents(sess, trial);
            
            figure; hold on;
            for i = 1:numChans %for each channel in out data

                eventID = trialEvents(i).eventID;
                eventTimes = trialEvents(i).eventTimes;
                
                yAxis = zeros(1, length(xAxis));
                if isempty(eventID)
                    return
                end

                eventInd = 1;
                eventVal = ~eventID(eventInd);
                for k = 1:length(xAxis)
                    if eventInd > length(eventTimes)
                        yAxis(k) = eventVal;
                    elseif xAxis(k) < (eventTimes(eventInd)*samplingFreq)
                        yAxis(k) = eventVal;
                    else
                        eventInd = eventInd+1;
                        eventVal = ~eventVal;
                        yAxis(k) = eventVal;
                    end
                end
                xVal = (xAxis-min(xAxis))/samplingFreq*1000;
                plot(xVal, yAxis+2*(i-1));
                axis([xVal(1), xVal(end), -.5, 2*numChans]);
                hold on;
            end
        end
        
        % gets the duration of frame and stim for all trials of a session.
        function [trialNumber, frameDuration, stimDuration] = getFrameStimDuration(sess)
            maxTrial = getMaxTrial(sess);  
            minTrial = getMinTrial(sess);
            
            numTrials = maxTrial-minTrial;
            frameStart = zeros(1, numTrials);
            frameStop = zeros(1,numTrials);
            
            stimStart = zeros(1, numTrials);
            stimStop = zeros(1, numTrials);
            
            j = 1;
            for i = minTrial:maxTrial %for each trial
                trialEvents = getTrialEvents(sess, i);
                if isempty(trialEvents(2).eventTimes) %if no frame data
                    frameStart(j) = 0;
                    frameStop(j) = 0;
                else
                    frameStart(j) = trialEvents(2).eventTimes(1);
                    frameStop(j) = trialEvents(2).eventTimes(end);
                end
                if isempty(trialEvents(3).eventTimes)  % if no stim data
                    stimStart(j) = 0;
                    stimStop(j) = 0;
                else
                    stimStart(j) = trialEvents(3).eventTimes(1);
                    stimStop(j) = trialEvents(3).eventTimes(end);
                end
                j = j+1;
            end
            frameDuration = frameStop-frameStart;
            stimDuration = stimStop-stimStart;
            trialNumber = minTrial:maxTrial;
            
            plotOn = false;
            if plotOn
                figure;
                plot((stimStop-stimStart),(frameStop-frameStart),'k.');
                hold on;
                plot([0 max((frameStop-frameStart),(stimStop-stimStart))],[0 max((frameStop-frameStart),(stimStop-stimStart))],'k');
                axis square;
                
            end
        end
        
        %to add more information to eventData class
        function sess = addToEventData(sess)
            sess.eventData = eventData(['D:\FullRecordedData\',sess.sessionFolder]);
            %sess.eventData = eventData();
            
            fname = saveSession(sess);
            %fname = saveSessionGUI(sess);
        end
        function sess = addToEventDataGUI(sess)
            sess.eventData = eventData(['D:\FullRecordedData\',sess.sessionFolder]);
            %sess.eventData = eventData();
            
            %fname = saveSession(sess);
            fname = saveSessionGUI(sess);
        end
        
        function fileName = saveSession(sess)  % save session as a struct to mat file
            fileName = [sess.sessionFolder,'_',int2str(now),'.mat'];
            save(fileName,'sess', '-v7.3'); %for some reason wouldnt save correctly unless '-v7.3' command added
        end
        
        function fileName = saveSessionGUI(sess)  % save session as a struct to mat file
            fileName = [sess.sessionFolder,'_',int2str(now),'_Inspected.mat'];
            save(fileName,'sess', '-v7.3'); %for some reason wouldnt save correctly unless '-v7.3' command added
        end
        
        %% Manipulating and plotting data in the session
        function [corrList, lag] = getXCorr(sess, unitIdent, lag, bin, plotOn)
            if ~exist('plotOn','var') || isempty(plotOn)
                plotOn = false;
            end
            
            corrList = zeros(sess.numUnits, lag*2+1);
            counter = 1;
            
            refUnit = sess.trodes(unitIdent(1)).units(unitIdent(2));
            
            for i = 1:length(sess.trodes)
                for j = 1:length(sess.trodes(i).units)
                    [corr, lag] = crossCorr(refUnit, sess.trodes(i).units(j), lag, bin);
                    
                    corrList(counter,:) = corr;
                    
                    counter = counter + 1;
                end
            end
            
            if plotOn
                [xx, yy] = getGoodArrangement(sess.numUnits);
                for i = 1:sess.numUnits
                    subplot(xx,yy,i);
                    hold on;
                    plot(corrList(i,:));
                end
            end
        end

        function sess = plotSingleUnits(sess, trode)
            tr = sess.trodes(trode);
        
            if isempty(tr.units)
                error('No Single Units');
            else
                for i = 1:length(tr.units)
                    subplot(2,ceil(length(tr.units)/2),i);
                    wv = [];
                    for k = 1:4
                        wv = [wv tr.units(i).waveform(:,:,k)];
                    end
                    plot(wv');
                end
            end
        end
        
        %note, combines but does not sort after combination.
        function sess = combineSingleUnits(sess, trodeNum, unitNum1, unitNum2) 
        
            if unitNum1 < 1 || unitNum2 < 1
                error('unit number must be positive');
            end
            if unitNum1 == unitNum2
                error('must refer to different units');
            end
            maxLen = length(sess.trodes(trodeNum).units);
            if unitNum1 > maxLen || unitNum2 > maxLen
                error('index out of bounds');
            end  
            
            unit1 = sess.trodes(trodeNum).units(unitNum1);
            unit2 = sess.trodes(trodeNum).units(unitNum2);
            
            unit1.index = [unit1.index; unit2.index];
            unit1.timestamp = [unit1.timestamp; unit2.timestamp];
            unit1.waveform = [unit1.waveform; unit2.waveform];
            
            %change order of timestamps, index, waveform of unit1 here. (or
            %maybe keep unordered for easier seperation in the future).
            
            %find(diff(sess.trodes(trodeNum).units(unit1).index) < 0)
            %this finds index of start of unit2's data.
            
            sess.trodes(trodeNum).units(unitNum1) = unit1;
            sess.trodes(trodeNum).units(unitNum2) = [];
        
        end
        
        function out = numTrodes(sess)
            out = length(sess.trodes);
        end
        
        function numUnits = numUnits(sess)
            numUnits = 0;
            for i = 1:length(sess.trodes)
                numUnits = numUnits + sess.trodes(i).numUnits;
            end
        end
        
        function allUnits = collateUnits(sess)
            numUnits = sess.numUnits();
            allUnits(numUnits) = singleUnit(NaN,NaN,NaN,NaN,NaN,NaN);
            error('does not run currently');
        end
        
        function plotWaveforms(sess)
            numUnits = sess.numUnits();
            [xx, yy, numFigs] = getGoodArrangement(numUnits);
            k = 1;
            for i = 1:length(sess.trodes)
                for j = 1:length(sess.trodes(i).units)
                    singleUnit = sess.trodes(i).units(j);
                    [waveFormAvg, ~]  = getAvgWaveform(singleUnit);
                    subplot(xx, yy, k); hold on;
                    waveFormLength = size(waveFormAvg,1);
                    for z = 1:size(singleUnit.waveform,3)
                        plot((z-1)*waveFormLength+(1:waveFormLength),waveFormAvg(:,z));
                    end
                    k = k+1;
                    set(gca,'xtick',[]);
                end
            end
        end
        
        function out = getReport(sess)
            numTrodes = sess.numTrodes();
            % get the autonomous details for each trode
            for i = 1:numTrodes
                fprintf('trode %d of %d\n',i,numTrodes);
                out.trodeDetails{i}.chans = sess.trodes(i).chans;
                out.trodeDetails{i}.report = sess.trodes(i).getReport();
            end
        end
        
        function raster = getRaster(sess, what, wrt)
        end
        
        %% Manipulating the history
        function sess = flushHistory(sess)
            sess.history = {};
        end
        
        function displayHistory(sess)
            if ~isempty(sess.history)
                fprintf('#\tTYPE\tIDENT\t\t\t\t\t\tMESSAGE\n')
            end
            fprintf('%s\n',sess.history{1});
            for i = 2:length(sess.history)
                if isstruct(sess.history{i}{3})
                    fprintf('%d.\t%s\t%s\t\t\t\t\t\tERROR\n',i,sess.history{i}{1},sess.history{i}{2});
                else
                    try
                        fprintf('%d.\t%s\t%s\t\t\t\t\t\t%s\n',i,sess.history{i}{1},sess.history{i}{2},sess.history{i}{3});
                    catch ex
                        fprintf('%d.\t%s\n',i,sess.history{i});
                    end
                end
            end
        end
        
        function sess = addToHistory(sess,type,details)
            switch lower(type)
                case {'err','error'}
                    % details is exception object
                    sess.history{end+1} = {'Err.',details.identifier,details.message,details.stack};
                case 'completed'
                    sess.history{end+1} = {'Comp.',details.identifier,details.message};
                case 'warning'
                    sess.history{end+1} = {'Warning.', details.identifier,details.message,details.data};
            end
        end
        
    end
    
end