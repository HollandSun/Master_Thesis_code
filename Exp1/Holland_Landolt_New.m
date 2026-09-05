function p = Holland_Landolt_Exp2
% Holland_Landolt_Exp2
%
% Exp2 sequence:
%   fixation -> one location cue -> two yellow circles -> task screen ->
%   target-location retention -> trial feedback.
%
% On a SHIFT trial, the initially attended circle turns blue and the
% participant reports the Landolt-C in the opposite yellow circle.
% On a HOLD trial, the initially attended circle turns red and the
% participant reports the Landolt-C in that same red circle.
%
% Response mapping:
%   Z = left-facing Landolt-C
%   M = right-facing Landolt-C
%   ESCAPE three times rapidly = end the experiment early

AssertOpenGL;
KbName('UnifyKeyNames');
rng('shuffle');

%% Participant/session information
subjectNumber = input('Enter Subject Number: ');
if ~isscalar(subjectNumber) || ~isnumeric(subjectNumber) || ...
        isnan(subjectNumber) || subjectNumber < 0 || ...
        fix(subjectNumber) ~= subjectNumber
    error('Subject number must be one non-negative integer.');
end

sessionStamp = datestr(now, 'yyyymmdd_HHMMSS');
scriptRoot = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptRoot, 'Data_Exp2');
diaryDir = fullfile(scriptRoot, 'Diaries_Exp2');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
if ~exist(diaryDir, 'dir'), mkdir(diaryDir); end

p.ExperimentName = 'AttentionShift_Landolt_Exp2';
p.ScriptVersion = '1.1_frame_based_task_timing';
p.Subject = subjectNumber;
p.SessionStamp = sessionStamp;
p.RandomStateAtStart = rng;

%% =====================================================================
%  DESIGN PARAMETERS -- edit block/trial proportions only in this section
%  =====================================================================
p.Design.NumBlocks = 8;
p.Design.TrialsPerBlock = 80;
p.Design.ShiftProbabilityMostlyShift = 0.70;
p.Design.ShiftProbabilityMostlyHold = 0.30;
p.Design.QuitPressCount = 3;

%% =====================================================================
%  TIMING PARAMETERS -- all durations are together here (frames/seconds)
%  =====================================================================
p.Timing.FixationSeconds = 0.500;
p.Timing.SingleLocationCueSeconds = 0.250;

% Frame-based task timing. The randomly sampled task delay is selected
% uniformly from MIN:RANDOM_UNIT:MAX, inclusive. At 60 Hz the defaults are
% 0.5-1.5 seconds in 1-frame steps. Change these three values directly.
p.Timing.TaskDelayRangeFrames = [30, 90]; % [minimum, maximum]
p.Timing.TaskDelayRandomUnitFrames = 1;   % random step size

% This deadline is anchored to TWO-CIRCLE ONSET. With the defaults, the
% available response window is 90-30 frames (1.5-0.5 s at 60 Hz).
p.Timing.TwoCircleToResponseDeadlineFrames = 120;

% A target-only circle remains through the common response deadline and
% for this additional fixed interval. Feedback then appears on every
% normally completed trial.
p.Timing.TargetRetentionAfterDeadlineSeconds = 1.000;
p.Timing.FeedbackSeconds = 0.500;
p.Timing.QuitMaxInterPressSeconds = 0.500;

%% =====================================================================
%  STIMULUS PARAMETERS -- all colors, sizes, and positions are here
%  =====================================================================
p.Stimulus.BackgroundColor = [128, 128, 128];
p.Stimulus.FixationColor = [0, 0, 0];
p.Stimulus.NeutralCircleColor = [255, 255, 0]; % yellow
p.Stimulus.ShiftCueColor = [0, 114, 255];       % blue
p.Stimulus.HoldCueColor = [255, 0, 0];          % red
p.Stimulus.CircleOutlineColor = [0, 0, 0];
p.Stimulus.LandoltColor = [0, 0, 0];
p.Stimulus.FeedbackCorrectColor = [0, 170, 0];
p.Stimulus.FeedbackIncorrectColor = [200, 0, 0];

% Feedback content is deliberately editable independently of scoring.
p.Stimulus.FeedbackCorrectText = '+';
p.Stimulus.FeedbackIncorrectText = '-';

p.Stimulus.HorizontalOffsetPx = 430;
p.Stimulus.CircleRadiusPx = 260;
p.Stimulus.CircleOutlineWidthPx = 5;
p.Stimulus.LandoltOuterRadiusPx = 15;
p.Stimulus.LandoltInnerRadiusPx = 8;
p.Stimulus.LandoltGapHalfWidthPx = 4;
p.Stimulus.FixationTextSizePx = 34;
p.Stimulus.FeedbackTextSizePx = 64;
p.Stimulus.InstructionTextSizePx = 30;

validateParameters(p);
p.BlockOrderCode = generateRandomBlockOrder(p.Design.NumBlocks);
p.OutputBase = fullfile(dataDir, sprintf('S%03d_%s_Exp2', ...
    p.Subject, p.SessionStamp));
diary(fullfile(diaryDir, sprintf('S%03d_%s_Exp2_diary.txt', ...
    p.Subject, p.SessionStamp)));

window = [];
p.KeyboardIndex = [];
cleanupObject = onCleanup(@localCleanup); %#ok<NASGU>

try
    PsychDefaultSetup(1);
    screens = Screen('Screens');
    p.ScreenNumber = max(screens);
    [window, p.WindowRect] = Screen('OpenWindow', p.ScreenNumber, ...
        p.Stimulus.BackgroundColor);
    Screen('BlendFunction', window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    Screen('TextFont', window, 'Arial');
    HideCursor(p.ScreenNumber);
    ListenChar(2);

    p.ifi = Screen('GetFlipInterval', window);
    p.MeasuredHz = 1 / p.ifi;
    p.slack = p.ifi / 2;

    [screenCx, screenCy] = RectCenter(p.WindowRect);
    requestedOffset = p.Stimulus.HorizontalOffsetPx;
    horizontalOffset = min(requestedOffset, RectWidth(p.WindowRect) * 0.30);
    availableRadius = floor(min([ ...
        RectWidth(p.WindowRect)/2-horizontalOffset-20, ...
        RectHeight(p.WindowRect)/2-20]));
    p.Stimulus.CircleRadiusPx = min( ...
        p.Stimulus.CircleRadiusPx, availableRadius);
    if p.Stimulus.CircleRadiusPx <= p.Stimulus.LandoltOuterRadiusPx
        error('The display is too narrow for the configured circles.');
    end

    p.Stimulus.CenterXY = [screenCx, screenCy];
    p.Stimulus.LocationXY = [screenCx-horizontalOffset, screenCy; ...
                             screenCx+horizontalOffset, screenCy];
    p.Stimulus.CircleRects = zeros(2, 4);
    for side = 1:2
        p.Stimulus.CircleRects(side, :) = CenterRectOnPointd( ...
            [0, 0, 2*p.Stimulus.CircleRadiusPx, ...
             2*p.Stimulus.CircleRadiusPx], ...
            p.Stimulus.LocationXY(side, 1), ...
            p.Stimulus.LocationXY(side, 2));
    end

    [keyboardIndices, keyboardNames] = GetKeyboardIndices;
    if isempty(keyboardIndices)
        error('No keyboard device was detected by Psychtoolbox.');
    end
    keyboardPosition = max(1, numel(keyboardIndices)-1);
    p.KeyboardIndex = keyboardIndices(keyboardPosition);
    p.KeyboardName = keyboardNames{keyboardPosition};

    p.Key.Z = KbName('z');
    p.Key.M = KbName('m');
    p.Key.Escape = KbName('ESCAPE');
    p.Key.Space = KbName('space');
    keyList = zeros(1, 256);
    keyList([p.Key.Z, p.Key.M]) = 1;
    KbQueueCreate(p.KeyboardIndex, keyList);

    fprintf('\nExp2 monitor: %.3f Hz (IFI %.4f ms)\n', ...
        p.MeasuredHz, p.ifi*1000);
    fprintf('Random block order: %s\n', p.BlockOrderCode);
    fprintf('Keyboard device: %s (index %d)\n', ...
        p.KeyboardName, p.KeyboardIndex);
    fprintf(['Task delay candidates: %d:%d:%d frames ' ...
        '(%.1f-%.1f ms on this monitor).\n'], ...
        p.Timing.TaskDelayRangeFrames(1), ...
        p.Timing.TaskDelayRandomUnitFrames, ...
        p.Timing.TaskDelayRangeFrames(2), ...
        p.Timing.TaskDelayRangeFrames(1)*p.ifi*1000, ...
        p.Timing.TaskDelayRangeFrames(2)*p.ifi*1000);
    fprintf(['Common deadline: %d frames after two-circle onset; ' ...
        'available response window: %d-%d frames (%.1f-%.1f ms).\n\n'], ...
        p.Timing.TwoCircleToResponseDeadlineFrames, ...
        p.Timing.TwoCircleToResponseDeadlineFrames - ...
        p.Timing.TaskDelayRangeFrames(2), ...
        p.Timing.TwoCircleToResponseDeadlineFrames - ...
        p.Timing.TaskDelayRangeFrames(1), ...
        (p.Timing.TwoCircleToResponseDeadlineFrames - ...
         p.Timing.TaskDelayRangeFrames(2))*p.ifi*1000, ...
        (p.Timing.TwoCircleToResponseDeadlineFrames - ...
         p.Timing.TaskDelayRangeFrames(1))*p.ifi*1000);

    p.PlannedTrials = cell(1, p.Design.NumBlocks);
    for blockNumber = 1:p.Design.NumBlocks
        p.PlannedTrials{blockNumber} = buildBlockTrials(p, blockNumber);
    end
    auditPlannedTrials(p);
    p.RandomStateAfterPlanning = rng;
    p.Results = repmat(emptyTrialResult(), 1, ...
        p.Design.NumBlocks*p.Design.TrialsPerBlock);
    p.CompletedTrials = 0;
    p.QuitRequested = false;
    p.CompletedSuccessfully = false;

    Priority(MaxPriority(window));

    for blockNumber = 1:p.Design.NumBlocks
        p.CurrentBlock = blockNumber;
        drawBlockStart(window, p, blockNumber);
        if strcmp(waitForSpaceOrQuit(p), 'quit')
            p.QuitRequested = true;
            break;
        end

        blockResultIndices = [];
        for trialNumber = 1:p.Design.TrialsPerBlock
            tr = p.PlannedTrials{blockNumber}(trialNumber);
            [trialResult, quitNow] = runTrial(window, p, tr, ...
                blockNumber, trialNumber);

            p.CompletedTrials = p.CompletedTrials + 1;
            p.Results(p.CompletedTrials) = trialResult;
            blockResultIndices(end+1) = p.CompletedTrials; %#ok<AGROW>

            if quitNow
                p.QuitRequested = true;
                break;
            end
        end

        saveSession(p);
        if p.QuitRequested
            break;
        end

        blockAccuracy = calculateAccuracy(p.Results(blockResultIndices));
        fprintf('Block %d accuracy: %.1f%%\n', blockNumber, blockAccuracy);
        if blockNumber < p.Design.NumBlocks
            drawBreakScreen(window, p, blockNumber, blockAccuracy);
            if strcmp(waitForSpaceOrQuit(p), 'quit')
                p.QuitRequested = true;
                break;
            end
        end
    end

    p.CompletedSuccessfully = ~p.QuitRequested && ...
        p.CompletedTrials == p.Design.NumBlocks*p.Design.TrialsPerBlock;
    p.EndTime = datestr(now, 30);
    saveSession(p);
    drawEndScreen(window, p);
    WaitSecs(2);

catch ME
    p.CompletedSuccessfully = false;
    p.EndTime = datestr(now, 30);
    p.ErrorMessage = ME.message;
    p.ErrorReport = getReport(ME, 'extended', 'hyperlinks', 'off');
    try
        saveSession(p);
    catch saveME
        fprintf(2, 'Emergency save also failed: %s\n', saveME.message);
    end
    rethrow(ME);
end

    function localCleanup
        Priority(0);
        try
            if ~isempty(p.KeyboardIndex) %#ok
                KbQueueStop(p.KeyboardIndex);
                KbQueueRelease(p.KeyboardIndex);
            end
        catch
        end
        Screen('CloseAll');
        ShowCursor;
        ListenChar(0);
        diary off;
    end
end


function validateParameters(p)
if fix(p.Design.NumBlocks) ~= p.Design.NumBlocks || ...
        mod(p.Design.NumBlocks, 2) ~= 0 || p.Design.NumBlocks < 2
    error('NumBlocks must be an even integer of at least two.');
end
if p.Design.TrialsPerBlock < 4 || ...
        fix(p.Design.TrialsPerBlock) ~= p.Design.TrialsPerBlock
    error('TrialsPerBlock must be an integer of at least four.');
end
probabilities = [p.Design.ShiftProbabilityMostlyShift, ...
    p.Design.ShiftProbabilityMostlyHold];
if any(probabilities <= 0) || any(probabilities >= 1)
    error('Both shift probabilities must be strictly between zero and one.');
end
frameRange = p.Timing.TaskDelayRangeFrames;
frameUnit = p.Timing.TaskDelayRandomUnitFrames;
frameDeadline = p.Timing.TwoCircleToResponseDeadlineFrames;
if numel(frameRange) ~= 2 || any(~isfinite(frameRange)) || ...
        any(frameRange < 1) || any(fix(frameRange) ~= frameRange) || ...
        frameRange(2) < frameRange(1)
    error('TaskDelayRangeFrames must contain [minimum maximum] integers.');
end
if ~isscalar(frameUnit) || ~isfinite(frameUnit) || frameUnit < 1 || ...
        fix(frameUnit) ~= frameUnit
    error('TaskDelayRandomUnitFrames must be one positive integer.');
end
if mod(frameRange(2)-frameRange(1), frameUnit) ~= 0
    error(['The task-delay range must be exactly divisible by ' ...
        'TaskDelayRandomUnitFrames so both endpoints are candidates.']);
end
if ~isscalar(frameDeadline) || ~isfinite(frameDeadline) || ...
        fix(frameDeadline) ~= frameDeadline || frameDeadline <= frameRange(2)
    error(['The common response deadline must be later than the largest ' ...
        'task-delay frame count.']);
end
timingValues = [p.Timing.FixationSeconds, ...
    p.Timing.SingleLocationCueSeconds, ...
    p.Timing.TargetRetentionAfterDeadlineSeconds, ...
    p.Timing.FeedbackSeconds, ...
    p.Timing.QuitMaxInterPressSeconds];
if any(timingValues < 0)
    error('Timing values cannot be negative.');
end
end


function auditPlannedTrials(p)
% Verify proportions, factor balance, timing, and location continuity before
% the participant can start. This also protects the design from later edits.
if numel(p.PlannedTrials) ~= p.Design.NumBlocks
    error('Planned block count does not match NumBlocks.');
end
for blockNumber = 1:p.Design.NumBlocks
    trials = p.PlannedTrials{blockNumber};
    if numel(trials) ~= p.Design.TrialsPerBlock
        error('Block %d does not contain the configured trial count.', ...
            blockNumber);
    end

    if p.BlockOrderCode(blockNumber) == 'S'
        expectedShift = round(p.Design.TrialsPerBlock * ...
            p.Design.ShiftProbabilityMostlyShift);
    else
        expectedShift = round(p.Design.TrialsPerBlock * ...
            p.Design.ShiftProbabilityMostlyHold);
    end
    if sum([trials.TrialTypeCode] == 1) ~= expectedShift
        error('Shift/hold proportion audit failed in block %d.', blockNumber);
    end

    for trialTypeCode = 1:2
        typeMask = [trials.TrialTypeCode] == trialTypeCode;
        congruencies = [trials(typeMask).Congruent];
        if abs(sum(congruencies == 1)-sum(congruencies == 0)) > 1
            error('Congruency balance audit failed in block %d.', blockNumber);
        end
        for congruent = 0:1
            cellMask = typeMask & [trials.Congruent] == congruent;
            directions = [trials(cellMask).TargetDirectionCode];
            if ~isempty(directions) && ...
                    abs(sum(directions == 1)-sum(directions == 2)) > 1
                error('Target-direction balance audit failed in block %d.', ...
                    blockNumber);
            end
        end
    end

    for trialNumber = 1:numel(trials)
        tr = trials(trialNumber);
        if tr.CueLocation ~= tr.InitialLocation || ...
                tr.EndLocation ~= tr.TargetLocation
            error('Cue/end location audit failed in block %d trial %d.', ...
                blockNumber, trialNumber);
        end
        if (tr.TrialTypeCode == 1 && ...
                tr.TargetLocation ~= 3-tr.InitialLocation) || ...
                (tr.TrialTypeCode == 2 && ...
                tr.TargetLocation ~= tr.InitialLocation)
            error('Shift/hold target audit failed in block %d trial %d.', ...
                blockNumber, trialNumber);
        end
        if trialNumber > 1 && tr.InitialLocation ~= ...
                trials(trialNumber-1).EndLocation
            error('Location-chain audit failed in block %d trial %d.', ...
                blockNumber, trialNumber);
        end
        if tr.TaskDelayFrames < p.Timing.TaskDelayRangeFrames(1) || ...
                tr.TaskDelayFrames > p.Timing.TaskDelayRangeFrames(2) || ...
                mod(tr.TaskDelayFrames-p.Timing.TaskDelayRangeFrames(1), ...
                p.Timing.TaskDelayRandomUnitFrames) ~= 0 || ...
                tr.ScheduledAvailableResponseFrames ~= ...
                p.Timing.TwoCircleToResponseDeadlineFrames- ...
                tr.TaskDelayFrames || ...
                tr.ScheduledAvailableResponseFrames <= 0
            error('Frame-delay/deadline audit failed in block %d trial %d.', ...
                blockNumber, trialNumber);
        end
    end
end
end


function blockOrder = generateRandomBlockOrder(numBlocks)
% Equal S/H block counts; reject any run of three identical blocks.
baseOrder = [repmat('S', 1, numBlocks/2), ...
             repmat('H', 1, numBlocks/2)];
for attempt = 1:10000
    candidate = baseOrder(randperm(numBlocks));
    hasThreeShift = ~isempty(strfind(candidate, 'SSS')); %#ok<STREMP>
    hasThreeHold = ~isempty(strfind(candidate, 'HHH')); %#ok<STREMP>
    if ~hasThreeShift && ~hasThreeHold
        blockOrder = candidate;
        return;
    end
end
error('Could not generate a valid randomized block order.');
end


function trials = buildBlockTrials(p, blockNumber)
blockCode = p.BlockOrderCode(blockNumber);
if blockCode == 'S'
    blockLabel = 'mostly-shift';
    shiftProbability = p.Design.ShiftProbabilityMostlyShift;
else
    blockLabel = 'mostly-hold';
    shiftProbability = p.Design.ShiftProbabilityMostlyHold;
end

nTrials = p.Design.TrialsPerBlock;
nShift = round(nTrials*shiftProbability);
nHold = nTrials-nShift;

% Column 1: 1=shift, 2=hold. Column 2: 0=incongruent, 1=congruent.
rows = zeros(nTrials, 2);
rowIndex = 1;
trialTypeCounts = [nShift, nHold];
for trialTypeCode = 1:2
    nType = trialTypeCounts(trialTypeCode);
    congruencies = [zeros(1, floor(nType/2)), ...
                    ones(1, floor(nType/2))];
    if mod(nType, 2) == 1
        congruencies(end+1) = randi(2)-1;
    end
    congruencies = congruencies(randperm(nType));
    indices = rowIndex:(rowIndex+nType-1);
    rows(indices, 1) = trialTypeCode;
    rows(indices, 2) = congruencies;
    rowIndex = rowIndex+nType;
end
rows = rows(randperm(nTrials), :);
targetDirections = balancedBinaryWithinCells(rows);

taskDelayCandidates = p.Timing.TaskDelayRangeFrames(1): ...
    p.Timing.TaskDelayRandomUnitFrames:p.Timing.TaskDelayRangeFrames(2);
taskDelayFrames = taskDelayCandidates( ...
    randi(numel(taskDelayCandidates), 1, nTrials));

trials = repmat(emptyPlannedTrial(), 1, nTrials);
currentAttendedLocation = randi(2);
for t = 1:nTrials
    tr = emptyPlannedTrial();
    tr.BlockTypeCode = blockCode;
    tr.BlockType = blockLabel;
    tr.BlockShiftProbability = shiftProbability;
    tr.TrialTypeCode = rows(t, 1);
    if tr.TrialTypeCode == 1
        tr.TrialType = 'shift';
    else
        tr.TrialType = 'hold';
    end

    tr.Congruent = rows(t, 2);
    if tr.Congruent
        tr.Congruency = 'congruent';
    else
        tr.Congruency = 'incongruent';
    end

    % The first trial of each block starts randomly. Thereafter, every
    % trial begins at the target/end location of the preceding trial.
    tr.InitialLocation = currentAttendedLocation;
    tr.CueLocation = tr.InitialLocation;
    if tr.TrialTypeCode == 1
        tr.TargetLocation = 3-tr.InitialLocation;
    else
        tr.TargetLocation = tr.InitialLocation;
    end
    tr.DistractorLocation = 3-tr.TargetLocation;
    tr.EndLocation = tr.TargetLocation;
    currentAttendedLocation = tr.EndLocation;

    tr.TargetDirectionCode = targetDirections(t);
    if tr.Congruent
        tr.DistractorDirectionCode = tr.TargetDirectionCode;
    else
        tr.DistractorDirectionCode = 3-tr.TargetDirectionCode;
    end
    tr.TaskDelayFrames = taskDelayFrames(t);
    tr.ScheduledTaskDelaySeconds = tr.TaskDelayFrames*p.ifi;
    tr.ScheduledAvailableResponseFrames = ...
        p.Timing.TwoCircleToResponseDeadlineFrames-tr.TaskDelayFrames;
    tr.ScheduledAvailableResponseSeconds = ...
        tr.ScheduledAvailableResponseFrames*p.ifi;
    trials(t) = tr;
end

% Make the spatial-continuity requirement fail loudly if future edits
% accidentally break the chain.
for t = 2:nTrials
    if trials(t).InitialLocation ~= trials(t-1).EndLocation
        error('Trial-location continuity failed while constructing block %d.', ...
            blockNumber);
    end
end
end


function values = balancedBinaryWithinCells(rows)
% Balance target left/right directions within Trial Type x Congruency.
[~, ~, groupIndex] = unique(rows, 'rows');
values = zeros(1, size(rows, 1));
oddGroups = find(mod(accumarray(groupIndex, 1), 2) == 1);
oddExtras = balancedBinary(numel(oddGroups));
extraIndex = 1;
for group = 1:max(groupIndex)
    indices = find(groupIndex == group);
    n = numel(indices);
    cellValues = [ones(1, floor(n/2)), 2*ones(1, floor(n/2))];
    if mod(n, 2) == 1
        cellValues(end+1) = oddExtras(extraIndex);
        extraIndex = extraIndex+1;
    end
    values(indices) = cellValues(randperm(n));
end
end


function values = balancedBinary(n)
nEach = floor(n/2);
values = [ones(1, nEach), 2*ones(1, nEach)];
if mod(n, 2) == 1
    values(end+1) = randi(2);
end
if n > 0
    values = values(randperm(n));
end
end


function [result, quitRequested] = runTrial(window, p, tr, ...
        blockNumber, trialNumber)
result = emptyTrialResult();
quitRequested = false;
rapidQuitDetected(p, true);

result.Subject = p.Subject;
result.Block = blockNumber;
result.Trial = trialNumber;
plannedFields = fieldnames(tr);
for fieldIndex = 1:numel(plannedFields)
    fieldName = plannedFields{fieldIndex};
    result.(fieldName) = tr.(fieldName);
end

% 1. Fixation alone.
drawFixationOnly(window, p);
[fixVBL, result.FixationOnset, ~, result.FixationMissed] = ...
    Screen('Flip', window);

% 2. One yellow circle at the location inherited from the previous trial.
drawSingleLocationCue(window, p, tr.CueLocation);
[~, result.SingleCueOnset, ~, result.SingleCueMissed] = ...
    Screen('Flip', window, ...
    fixVBL+p.Timing.FixationSeconds-p.slack);

% 3. Two yellow circles. This onset anchors the common response deadline.
drawTwoNeutralCircles(window, p);
[twoCircleVBL, result.TwoCircleOnset, ~, result.TwoCircleMissed] = ...
    Screen('Flip', window, ...
    result.SingleCueOnset+p.Timing.SingleLocationCueSeconds-p.slack);

result.ScheduledTaskOnset = twoCircleVBL+tr.TaskDelayFrames*p.ifi;
result.ResponseDeadline = twoCircleVBL+ ...
    p.Timing.TwoCircleToResponseDeadlineFrames*p.ifi;

% Prepare the task display, but keep the two yellow circles visible until
% the randomly selected task onset. Starting the queue shortly beforehand
% reduces the chance of losing a response made on the onset frame.
drawTaskDisplay(window, p, tr);
leadTime = max(0.010, 2*p.ifi);
quitRequested = waitUntilOrQuit(p, result.ScheduledTaskOnset-leadTime);
if quitRequested
    result.ResponseKey = 'task-abort';
    result.Accuracy = NaN;
    return;
end
KbQueueFlush(p.KeyboardIndex);
KbQueueStart(p.KeyboardIndex);
[~, result.TaskOnset, ~, result.TaskOnsetMissed] = ...
    Screen('Flip', window, result.ScheduledTaskOnset-p.slack);
result.ActualTaskDelaySeconds = ...
    result.TaskOnset-result.TwoCircleOnset;
result.ActualTaskDelayFrames = result.ActualTaskDelaySeconds/p.ifi;
result.ActualAvailableResponseSeconds = ...
    result.ResponseDeadline-result.TaskOnset;
result.ActualAvailableResponseFrames = ...
    result.ActualAvailableResponseSeconds/p.ifi;

[responseCode, responseTime, anticipated, quitDuringResponse] = ...
    pollForResponse(p, result.TaskOnset, result.ResponseDeadline);
result.AnticipatoryResponseDetected = anticipated;
if quitDuringResponse
    result.ResponseKey = 'task-abort';
    result.Accuracy = NaN;
    result.TimedOut = false;
    KbQueueStop(p.KeyboardIndex);
    quitRequested = true;
    return;
end

if responseCode == 0
    result.ResponseKey = 'none';
    result.ResponseDirection = '';
    result.Accuracy = 0;
    result.TimedOut = true;
else
    result.ResponseTime = responseTime;
    result.RT = responseTime-result.TaskOnset;
    result.TimedOut = false;
    if responseCode == p.Key.Z
        result.ResponseKey = 'z';
        result.ResponseDirection = 'left';
        result.Accuracy = double(tr.TargetDirectionCode == 1);
    elseif responseCode == p.Key.M
        result.ResponseKey = 'm';
        result.ResponseDirection = 'right';
        result.Accuracy = double(tr.TargetDirectionCode == 2);
    end
end
KbQueueStop(p.KeyboardIndex);

% As soon as a response is made (or at timeout), remove the non-target
% circle. The target-only screen then remains through the fixed common
% deadline and for the configured post-deadline retention interval.
drawTargetOnly(window, p, tr);
[~, result.TargetOnlyOnset, ~, result.TargetOnlyMissed] = ...
    Screen('Flip', window);

feedbackDue = result.ResponseDeadline + ...
    p.Timing.TargetRetentionAfterDeadlineSeconds;
quitRequested = waitUntilOrQuit(p, feedbackDue-leadTime);
if quitRequested
    result.ResponseKey = 'task-abort';
    result.ResponseDirection = '';
    result.Accuracy = NaN;
    return;
end

% 5. Per-trial feedback. Timeouts use the editable incorrect symbol.
if result.Accuracy == 1
    result.FeedbackText = p.Stimulus.FeedbackCorrectText;
else
    result.FeedbackText = p.Stimulus.FeedbackIncorrectText;
end
drawFeedback(window, p, result.Accuracy == 1);
[~, result.FeedbackOnset, ~, result.FeedbackMissed] = ...
    Screen('Flip', window, feedbackDue-p.slack);

feedbackEnd = result.FeedbackOnset+p.Timing.FeedbackSeconds;
quitRequested = waitUntilOrQuit(p, feedbackEnd);
if quitRequested
    result.ResponseKey = 'task-abort';
    result.ResponseDirection = '';
    result.Accuracy = NaN;
    return;
end

fprintf(['Block %d Trial %02d | %-5s | %-11s | %-11s | ' ...
    'start=%s target=%s | task delay %.2f fr | available %.2f fr | RT '], ...
    blockNumber, trialNumber, tr.TrialType, tr.BlockType, ...
    tr.Congruency, locationName(tr.InitialLocation), ...
    locationName(tr.TargetLocation), result.ActualTaskDelayFrames, ...
    result.ActualAvailableResponseFrames);
if isnan(result.RT)
    fprintf('NA');
else
    fprintf('%.0f ms', result.RT*1000);
end
fprintf(' | acc=%d\n', result.Accuracy);
end


function [responseCode, responseTime, anticipated, quitRequested] = ...
        pollForResponse(p, minTime, deadline)
responseCode = 0;
responseTime = NaN;
anticipated = false;
quitRequested = false;
while GetSecs < deadline
    [quitNow, ~] = rapidQuitDetected(p, false);
    if quitNow
        quitRequested = true;
        return;
    end
    [responseCode, responseTime, earlyPress] = ...
        readQueuedResponse(p, minTime, deadline);
    anticipated = anticipated || earlyPress;
    if responseCode ~= 0
        return;
    end
    WaitSecs('YieldSecs', 0.001);
end
[responseCode, responseTime, earlyPress] = ...
    readQueuedResponse(p, minTime, deadline);
anticipated = anticipated || earlyPress;
end


function [responseCode, responseTime, earlyPress] = ...
        readQueuedResponse(p, minTime, maxTime)
responseCode = 0;
responseTime = NaN;
earlyPress = false;
[responded, firstPress] = KbQueueCheck(p.KeyboardIndex);
if ~responded
    return;
end

allowedCodes = [p.Key.Z, p.Key.M];
pressTimes = firstPress(allowedCodes);
earlyPress = any(pressTimes > 0 & pressTimes < minTime);
eligible = pressTimes >= minTime & pressTimes <= maxTime;
if any(eligible)
    eligibleIndices = find(eligible);
    [responseTime, relativeIndex] = min(pressTimes(eligibleIndices));
    responseCode = allowedCodes(eligibleIndices(relativeIndex));
elseif earlyPress
    % KbQueue stores only the first press of each key. Clear an exclusively
    % premature press so a later valid press of the same key can be read.
    KbQueueFlush(p.KeyboardIndex);
end
end


function [quitDetected, detectionTime] = rapidQuitDetected(p, resetState)
% A held key counts once; three separate rapid ESCAPE down-events abort.
persistent escapePressCount lastEscapePressTime escapeWasDown activeKeyboard
if resetState || isempty(activeKeyboard) || activeKeyboard ~= p.KeyboardIndex
    escapePressCount = 0;
    lastEscapePressTime = NaN;
    escapeWasDown = false;
    activeKeyboard = p.KeyboardIndex;
    quitDetected = false;
    detectionTime = NaN;
    return;
end

quitDetected = false;
detectionTime = NaN;
[~, checkTime, keyCode] = KbCheck(p.KeyboardIndex);
escapeIsDown = keyCode(p.Key.Escape);
if escapeIsDown && ~escapeWasDown
    if isnan(lastEscapePressTime) || checkTime-lastEscapePressTime > ...
            p.Timing.QuitMaxInterPressSeconds
        escapePressCount = 1;
    else
        escapePressCount = escapePressCount+1;
    end
    lastEscapePressTime = checkTime;
    if escapePressCount >= p.Design.QuitPressCount
        quitDetected = true;
        detectionTime = checkTime;
        escapePressCount = 0;
        lastEscapePressTime = NaN;
    end
end
escapeWasDown = escapeIsDown;
end


function quitRequested = waitUntilOrQuit(p, endTime)
quitRequested = false;
while GetSecs < endTime
    [quitNow, ~] = rapidQuitDetected(p, false);
    if quitNow
        quitRequested = true;
        return;
    end
    WaitSecs('YieldSecs', 0.001);
end
end


function drawFixationOnly(window, p)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
drawFixation(window, p);
end


function drawSingleLocationCue(window, p, cueLocation)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
drawFilledCircle(window, p, cueLocation, ...
    p.Stimulus.NeutralCircleColor);
drawFixation(window, p);
end


function drawTwoNeutralCircles(window, p)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
for side = 1:2
    drawFilledCircle(window, p, side, p.Stimulus.NeutralCircleColor);
end
drawFixation(window, p);
end


function drawTaskDisplay(window, p, tr)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
circleColors = {p.Stimulus.NeutralCircleColor, ...
                p.Stimulus.NeutralCircleColor};
if tr.TrialTypeCode == 1
    circleColors{tr.CueLocation} = p.Stimulus.ShiftCueColor;
else
    circleColors{tr.CueLocation} = p.Stimulus.HoldCueColor;
end

for side = 1:2
    drawFilledCircle(window, p, side, circleColors{side});
end

targetXY = p.Stimulus.LocationXY(tr.TargetLocation, :);
distractorXY = p.Stimulus.LocationXY(tr.DistractorLocation, :);
drawLandoltC(window, p, targetXY, tr.TargetDirectionCode, ...
    p.Stimulus.LandoltColor, circleColors{tr.TargetLocation});
drawLandoltC(window, p, distractorXY, tr.DistractorDirectionCode, ...
    p.Stimulus.LandoltColor, circleColors{tr.DistractorLocation});
drawFixation(window, p);
end


function drawTargetOnly(window, p, tr)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
if tr.TrialTypeCode == 1
    targetCircleColor = p.Stimulus.NeutralCircleColor;
else
    targetCircleColor = p.Stimulus.HoldCueColor;
end
drawFilledCircle(window, p, tr.TargetLocation, targetCircleColor);
drawFixation(window, p);
end


function drawFilledCircle(window, p, side, fillColor)
rect = p.Stimulus.CircleRects(side, :);
Screen('FillOval', window, fillColor, rect);
Screen('FrameOval', window, p.Stimulus.CircleOutlineColor, rect, ...
    p.Stimulus.CircleOutlineWidthPx);
end


function drawLandoltC(window, p, centerXY, directionCode, ...
        landoltColor, surroundingColor)
outerRect = CenterRectOnPointd( ...
    [0, 0, 2*p.Stimulus.LandoltOuterRadiusPx, ...
     2*p.Stimulus.LandoltOuterRadiusPx], centerXY(1), centerXY(2));
innerRect = CenterRectOnPointd( ...
    [0, 0, 2*p.Stimulus.LandoltInnerRadiusPx, ...
     2*p.Stimulus.LandoltInnerRadiusPx], centerXY(1), centerXY(2));
Screen('FillOval', window, landoltColor, outerRect);
Screen('FillOval', window, surroundingColor, innerRect);

cx = centerXY(1);
cy = centerXY(2);
rOuter = p.Stimulus.LandoltOuterRadiusPx+1;
rInner = p.Stimulus.LandoltInnerRadiusPx-1;
g = p.Stimulus.LandoltGapHalfWidthPx;
switch directionCode
    case 1
        gapRect = [cx-rOuter, cy-g, cx-rInner, cy+g];
    case 2
        gapRect = [cx+rInner, cy-g, cx+rOuter, cy+g];
    otherwise
        error('Exp2 Landolt-C direction must be left (1) or right (2).');
end
Screen('FillRect', window, surroundingColor, gapRect);
end


function drawFixation(window, p)
Screen('TextSize', window, p.Stimulus.FixationTextSizePx);
drawCenteredTextAt(window, '+', p.Stimulus.CenterXY(1), ...
    p.Stimulus.CenterXY(2), p.Stimulus.FixationColor);
end


function drawFeedback(window, p, correct)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
Screen('TextSize', window, p.Stimulus.FeedbackTextSizePx);
if correct
    feedbackText = p.Stimulus.FeedbackCorrectText;
    feedbackColor = p.Stimulus.FeedbackCorrectColor;
else
    feedbackText = p.Stimulus.FeedbackIncorrectText;
    feedbackColor = p.Stimulus.FeedbackIncorrectColor;
end
DrawFormattedText(window, feedbackText, 'center', 'center', feedbackColor);
end


function drawCenteredTextAt(window, textString, cx, cy, color)
bounds = Screen('TextBounds', window, textString);
x = cx-RectWidth(bounds)/2;
y = cy-RectHeight(bounds)/2;
Screen('DrawText', window, textString, x, y, color);
end


function drawBlockStart(window, p, blockNumber)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
Screen('TextSize', window, p.Stimulus.InstructionTextSizePx);
message = sprintf(['Block %d of %d\n\n' ...
    'First look at the single yellow circle.\n\n' ...
    'BLUE = SHIFT: report the Landolt-C in the opposite yellow circle.\n' ...
    'RED = HOLD: report the Landolt-C in the red circle.\n\n' ...
    'Z = left gap, M = right gap.\n' ...
    'Press ESCAPE three times rapidly to end early.\n\n' ...
    'Press SPACE to begin.'], blockNumber, p.Design.NumBlocks);
DrawFormattedText(window, message, 'center', 'center', ...
    p.Stimulus.FixationColor, 80);
Screen('Flip', window);
end


function drawBreakScreen(window, p, blockNumber, accuracy)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
Screen('TextSize', window, p.Stimulus.InstructionTextSizePx);
message = sprintf(['Block %d complete.\n\nAccuracy: %.1f%%\n\n' ...
    'Take a break. Press SPACE when ready to continue.'], ...
    blockNumber, accuracy);
DrawFormattedText(window, message, 'center', 'center', ...
    p.Stimulus.FixationColor, 70);
Screen('Flip', window);
end


function drawEndScreen(window, p)
Screen('FillRect', window, p.Stimulus.BackgroundColor);
Screen('TextSize', window, p.Stimulus.InstructionTextSizePx);
if p.CompletedSuccessfully
    message = sprintf('The experiment is complete.\n\nThank you!');
else
    message = sprintf(['The experiment ended early.\n\n' ...
        'Available data were saved.']);
end
DrawFormattedText(window, message, 'center', 'center', ...
    p.Stimulus.FixationColor, 70);
Screen('Flip', window);
end


function choice = waitForSpaceOrQuit(p)
choice = '';
while KbCheck(p.KeyboardIndex)
    WaitSecs('YieldSecs', 0.01);
end
rapidQuitDetected(p, true);
while isempty(choice)
    [quitNow, ~] = rapidQuitDetected(p, false);
    if quitNow
        choice = 'quit';
        break;
    end
    [isDown, ~, keyCode] = KbCheck(p.KeyboardIndex);
    if isDown && keyCode(p.Key.Space)
        choice = 'space';
    elseif ~isDown
        WaitSecs('YieldSecs', 0.01);
    end
end
while KbCheck(p.KeyboardIndex)
    WaitSecs('YieldSecs', 0.01);
end
end


function accuracyPercent = calculateAccuracy(results)
values = [results.Accuracy];
values = values(~isnan(values));
if isempty(values)
    accuracyPercent = NaN;
else
    accuracyPercent = mean(values)*100;
end
end


function saveSession(p)
save([p.OutputBase '.mat'], 'p', '-v7');
if isfield(p, 'CompletedTrials') && p.CompletedTrials > 0
    completed = p.Results(1:p.CompletedTrials);
    writetable(struct2table(completed), [p.OutputBase '_trials.csv']);
end
end


function name = locationName(code)
names = {'left', 'right'};
name = names{code};
end


function tr = emptyPlannedTrial
tr = struct( ...
    'BlockTypeCode', '', ...
    'BlockType', '', ...
    'BlockShiftProbability', NaN, ...
    'TrialTypeCode', NaN, ...
    'TrialType', '', ...
    'Congruent', NaN, ...
    'Congruency', '', ...
    'InitialLocation', NaN, ...
    'CueLocation', NaN, ...
    'TargetLocation', NaN, ...
    'DistractorLocation', NaN, ...
    'EndLocation', NaN, ...
    'TargetDirectionCode', NaN, ...
    'DistractorDirectionCode', NaN, ...
    'TaskDelayFrames', NaN, ...
    'ScheduledTaskDelaySeconds', NaN, ...
    'ScheduledAvailableResponseFrames', NaN, ...
    'ScheduledAvailableResponseSeconds', NaN);
end


function result = emptyTrialResult
result = struct( ...
    'Subject', NaN, ...
    'Block', NaN, ...
    'Trial', NaN, ...
    'BlockTypeCode', '', ...
    'BlockType', '', ...
    'BlockShiftProbability', NaN, ...
    'TrialTypeCode', NaN, ...
    'TrialType', '', ...
    'Congruent', NaN, ...
    'Congruency', '', ...
    'InitialLocation', NaN, ...
    'CueLocation', NaN, ...
    'TargetLocation', NaN, ...
    'DistractorLocation', NaN, ...
    'EndLocation', NaN, ...
    'TargetDirectionCode', NaN, ...
    'DistractorDirectionCode', NaN, ...
    'TaskDelayFrames', NaN, ...
    'ScheduledTaskDelaySeconds', NaN, ...
    'ScheduledAvailableResponseFrames', NaN, ...
    'ScheduledAvailableResponseSeconds', NaN, ...
    'FixationOnset', NaN, ...
    'FixationMissed', NaN, ...
    'SingleCueOnset', NaN, ...
    'SingleCueMissed', NaN, ...
    'TwoCircleOnset', NaN, ...
    'TwoCircleMissed', NaN, ...
    'ScheduledTaskOnset', NaN, ...
    'TaskOnset', NaN, ...
    'TaskOnsetMissed', NaN, ...
    'ActualTaskDelaySeconds', NaN, ...
    'ActualTaskDelayFrames', NaN, ...
    'ActualAvailableResponseSeconds', NaN, ...
    'ActualAvailableResponseFrames', NaN, ...
    'ResponseDeadline', NaN, ...
    'ResponseTime', NaN, ...
    'ResponseKey', '', ...
    'ResponseDirection', '', ...
    'RT', NaN, ...
    'Accuracy', NaN, ...
    'TimedOut', false, ...
    'AnticipatoryResponseDetected', false, ...
    'TargetOnlyOnset', NaN, ...
    'TargetOnlyMissed', NaN, ...
    'FeedbackText', '', ...
    'FeedbackOnset', NaN, ...
    'FeedbackMissed', NaN);
end
