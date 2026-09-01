function p = Holland_Landolt_Main
% Holland_Landolt_Main
% Psychtoolbox implementation of the 2 (shift/hold) x 2 (mostly
% shift/mostly hold) x 2 (congruent/incongruent) x 3 (1 frame/200/400 ms)
% within-subjects Landolt-C experiment.
%
% Response mapping:
%   Z = left-facing target
%   M = right-facing target
%   ESCAPE three times rapidly = end the experiment early

AssertOpenGL;
KbName('UnifyKeyNames');
rng('shuffle');

%% Participant and session information
subjectNumber = input('Enter Subject Number: ');

if ~isscalar(subjectNumber) || ~isnumeric(subjectNumber) || ...
        isnan(subjectNumber) || subjectNumber < 0 || fix(subjectNumber) ~= subjectNumber
    error('Subject number must be one non-negative integer.');
end

sessionStamp = datestr(now, 'yyyymmdd_HHMMSS');
scriptRoot   = fileparts(mfilename('fullpath'));
dataDir      = fullfile(scriptRoot, 'Data');
diaryDir     = fullfile(scriptRoot, 'Diaries');
if ~exist(dataDir, 'dir'),  mkdir(dataDir);  end
if ~exist(diaryDir, 'dir'), mkdir(diaryDir); end

p.ExperimentName = 'AttentionShift_LandoltFlash';
p.ScriptVersion  = '2.2_simple_flash';
p.Subject        = subjectNumber;
p.Version        = 0; % fixed versions are no longer used; order is randomized
p.SessionStamp   = sessionStamp;
p.RandomState    = rng;
p.NumBlocks      = 8;
p.BlockOrderCode = generateRandomBlockOrder(p.NumBlocks);

%% Experimental settings (edit here if the design changes)
p.TrialsPerBlock               = 80;
% Adjust the shift/hold ratios for the two block types here. Hold
% probability is always 1 minus the corresponding shift probability.
p.ShiftProbabilityMostlyShift  = 0.70;
p.ShiftProbabilityMostlyHold   = 0.30;
p.NominalDelayLabels           = {'1-frame', '200-ms', '400-ms'};
p.NominalDelayMs               = [NaN, 200, 400];
p.InitialFixationSeconds        = 0.500;
p.SpatialCueSeconds            = 0.250;
p.PostSpatialCueRangeSeconds   = [0.500, 1.500];
p.ResponseDeadlineSeconds      = 1.500;
% FLASH SETTINGS: change these two values to adjust duration and contrast.
% Duration is an integer number of monitor frames. Contrast 0 matches the
% gray background; contrast 1 matches the ordinary black Landolt-C.
p.FlashDurationFrames          = 1;
p.FlashContrast                = 0.50;
p.InterTrialIntervalSeconds    = 1.000;
p.QuitPressCount               = 3;
p.QuitMaxInterPressSeconds     = 0.500;

% Congruency x Delay conditions are distributed as evenly as mathematically
% possible separately within shift and hold trials in every block.
nCellsWithinTrialType = numel(p.NominalDelayLabels) * 2;
probabilitiesToCheck = [p.ShiftProbabilityMostlyShift, ...
    p.ShiftProbabilityMostlyHold];
if any(probabilitiesToCheck <= 0) || any(probabilitiesToCheck >= 1)
    error('Both adjustable shift probabilities must be between 0 and 1.');
end
for probability = probabilitiesToCheck
    nShiftToCheck = round(p.TrialsPerBlock * probability);
    nHoldToCheck = p.TrialsPerBlock - nShiftToCheck;
    if nShiftToCheck < nCellsWithinTrialType || ...
            nHoldToCheck < nCellsWithinTrialType
        error(['Each trial type must have at least one trial in every ' ...
            'Congruency x Delay cell. Adjust the probabilities or increase ' ...
            'TrialsPerBlock.']);
    end
end

%% Display and stimulus settings
p.BackgroundColor      = [128, 128, 128];
p.ForegroundColor      = [0, 0, 0];
% Convert FlashContrast into a gray Landolt-C RGB value.
p.FlashLandoltColor    = round(p.BackgroundColor + p.FlashContrast .* ...
    (p.ForegroundColor - p.BackgroundColor));
p.PlaceholderRadiusPx  = 220;
p.PlaceholderLinePx    = 4;
p.SpatialCueLinePx     = 11;
p.LandoltOuterRadiusPx = 15;
p.LandoltInnerRadiusPx = 8;
p.LandoltGapHalfPx     = 4;
p.LandoltYOffsetPx     = 35;
p.ArrayYOffsetPx       = -40;
p.ArrayTextSizePx      = 64;
p.InstructionTextSize  = 30;

p.OutputBase = fullfile(dataDir, sprintf('S%03d_%s', ...
    p.Subject, p.SessionStamp));
diary(fullfile(diaryDir, sprintf('S%03d_%s_diary.txt', ...
    p.Subject, p.SessionStamp)));

window = [];
p.KeyboardIndex = [];
cleanupObject = onCleanup(@localCleanup); %#ok<NASGU>

try
    PsychDefaultSetup(1); 
    screens        = Screen('Screens');
    p.ScreenNumber = max(screens);
    [window, p.WindowRect] = Screen('OpenWindow', p.ScreenNumber, ...
        p.BackgroundColor);
    Screen('BlendFunction', window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    Screen('TextFont', window, 'Arial');
    HideCursor(p.ScreenNumber);
    ListenChar(2);

    p.ifi          = Screen('GetFlipInterval', window);
    p.MeasuredHz   = 1 / p.ifi;
    p.slack        = p.ifi / 2;
    p.DelayFrames  = [1, ...
        max(1, round(0.200 / p.ifi)), ...
        max(1, round(0.400 / p.ifi))];  % frame setting
    p.DelayActualMs = p.DelayFrames * p.ifi * 1000;

    [screenCx, screenCy] = RectCenter(p.WindowRect);
    % Move the two large placeholders farther toward the screen edges.
    horizontalOffset = min(430, RectWidth(p.WindowRect) * 0.30);
    % Keep the requested 220-px radius on normal lab displays, but prevent
    % clipping if the script is briefly run on a much narrower screen.
    availableRadius = floor(RectWidth(p.WindowRect)/2 - horizontalOffset - 20);
    p.PlaceholderRadiusPx = min(p.PlaceholderRadiusPx, availableRadius);
    p.CenterXY = [screenCx, screenCy];
    p.LocationXY = [screenCx - horizontalOffset, screenCy; ...
                    screenCx + horizontalOffset, screenCy];
    p.PlaceholderRects = zeros(2, 4);
    for side = 1:2
        p.PlaceholderRects(side, :) = CenterRectOnPointd( ...
            [0, 0, 2*p.PlaceholderRadiusPx, 2*p.PlaceholderRadiusPx], ...
            p.LocationXY(side, 1), p.LocationXY(side, 2));
    end

    [keyboardIndices, keyboardNames] = GetKeyboardIndices;
    if isempty(keyboardIndices)
        error('No keyboard device was detected by Psychtoolbox.');
    end
    % Preserve the legacy script's second-to-last-device choice when the
    % machine exposes multiple devices; fall back safely on a single-device
    % setup. The selected name and index are printed and saved at startup.
    keyboardPosition = max(1, numel(keyboardIndices) - 1);
    p.KeyboardIndex = keyboardIndices(keyboardPosition);
    p.KeyboardName  = keyboardNames{keyboardPosition};

    p.Key.Z      = KbName('z');
    p.Key.M      = KbName('m');
    p.Key.Escape = KbName('ESCAPE');
    p.Key.Space  = KbName('space');
    keyList = zeros(1, 256);
    keyList([p.Key.Z, p.Key.M]) = 1;
    KbQueueCreate(p.KeyboardIndex, keyList);

    fprintf('\nMonitor: %.3f Hz (IFI %.4f ms)\n', ...
        p.MeasuredHz, p.ifi * 1000);
    fprintf('Flash delays scheduled as %d, %d, and %d frames ', p.DelayFrames);
    fprintf('(%.3f, %.3f, %.3f ms).\n', p.DelayActualMs);
    fprintf('Random block order: %s\n', p.BlockOrderCode);
    fprintf('Keyboard device: %s (index %d)\n\n', ...
        p.KeyboardName, p.KeyboardIndex);

    p.PlannedTrials = cell(1, p.NumBlocks);
    p.Results = repmat(emptyTrialResult(), ...
        1, p.NumBlocks * p.TrialsPerBlock);
    p.CompletedTrials      = 0;
    p.QuitRequested        = false;
    p.CompletedSuccessfully = false;

    Priority(MaxPriority(window));

    for blockNumber = 1:p.NumBlocks
        p.CurrentBlock = blockNumber;
        p.PlannedTrials{blockNumber} = buildBlockTrials(p, blockNumber);

        drawBlockStart(window, p, blockNumber);
        startChoice = waitForSpaceOrQuit(p);
        if strcmp(startChoice, 'quit')
            p.QuitRequested = true;
            break;
        end

        blockResultIndices = [];
        for trialNumber = 1:p.TrialsPerBlock
            plannedTrial = p.PlannedTrials{blockNumber}(trialNumber);
            [trialResult, quitNow] = runTrial(window, p, ...
                plannedTrial, blockNumber, trialNumber);

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

        if blockNumber < p.NumBlocks
            drawBreakScreen(window, p, blockNumber, blockAccuracy);
            breakChoice = waitForSpaceOrQuit(p);
            if strcmp(breakChoice, 'quit')
                p.QuitRequested = true;
                break;
            end
        end
    end

    p.CompletedSuccessfully = ~p.QuitRequested && ...
        p.CompletedTrials == p.NumBlocks * p.TrialsPerBlock;
    p.EndTime = datestr(now, 30);
    saveSession(p);

    drawEndScreen(window, p);
    WaitSecs(2);

catch ME
    p.CompletedSuccessfully = false;
    p.EndTime = datestr(now, 30);
    p.ErrorMessage = ME.message;
    p.ErrorReport  = getReport(ME, 'extended', 'hyperlinks', 'off');
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
            if ~isempty(p.KeyboardIndex)  %#ok
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


function blockOrder = generateRandomBlockOrder(numBlocks)
% Use equal numbers of mostly-shift (S) and mostly-hold (H) blocks. The
% order is randomized anew for each session, rejecting SSS and HHH runs.

baseOrder = [repmat('S', 1, numBlocks/2), ...
             repmat('H', 1, numBlocks/2)];
for attempt = 1:10000 
    candidate = baseOrder(randperm(numBlocks));
    hasThreeShift = ~isempty(strfind(candidate, 'SSS')); %#ok<STREMP>
    hasThreeHold  = ~isempty(strfind(candidate, 'HHH')); %#ok<STREMP>
    if ~hasThreeShift && ~hasThreeHold
        blockOrder = candidate;
        return;
    end
end
error('Could not generate a valid randomized block order.');
end


function trials = buildBlockTrials(p, blockNumber)
% Distribute Delay x Congruency cells as evenly as possible separately for
% shift and hold, including balanced delay and congruency margins.

blockCode = p.BlockOrderCode(blockNumber);
if blockCode == 'S'
    blockLabel = 'mostly-shift';
    blockShiftProbability = p.ShiftProbabilityMostlyShift;
else
    blockLabel = 'mostly-hold';
    blockShiftProbability = p.ShiftProbabilityMostlyHold;
end
nShift = round(p.TrialsPerBlock * blockShiftProbability);
nHold = p.TrialsPerBlock - nShift;

rows = zeros(p.TrialsPerBlock, 3);
rowIndex = 1;
trialTypeCounts = [nShift, nHold];
for trialTypeCode = 1:2 % 1=shift, 2=hold
    cellCounts = balancedFactorCellCounts( ...
        trialTypeCounts(trialTypeCode), numel(p.NominalDelayLabels));

    cellIndex = 1;
    for delayCondition = 1:numel(p.NominalDelayLabels)
        for congruent = 0:1
            for repetition = 1:cellCounts(cellIndex) %#ok
                rows(rowIndex, :) = ...
                    [trialTypeCode, delayCondition, congruent];
                rowIndex = rowIndex + 1;
            end
            cellIndex = cellIndex + 1;
        end
    end
end
if rowIndex ~= p.TrialsPerBlock + 1
    error('Internal trial-generation error: unexpected block length.');
end
rows = rows(randperm(size(rows, 1)), :);

% Balance response-relevant and neutral directions within every factorial
% cell to within one trial, while retaining 50/50 balance across the block.
targetDirections  = balancedWithinCells(rows);
neutralDirections = balancedWithinCells(rows) + 2; % 3=up, 4=down

trials = repmat(emptyPlannedTrial(), 1, p.TrialsPerBlock);
currentAttendedLocation = randi(2); % first trial starts randomly
for t = 1:p.TrialsPerBlock
    tr = emptyPlannedTrial();
    tr.BlockTypeCode   = blockCode;
    tr.BlockType       = blockLabel;
    tr.BlockShiftProbability = blockShiftProbability;
    tr.TrialTypeCode   = rows(t, 1);
    if tr.TrialTypeCode == 1
        tr.TrialType = 'shift';
    else
        tr.TrialType = 'hold';
    end
    tr.DelayCondition  = rows(t, 2);
    tr.DelayLabel      = p.NominalDelayLabels{tr.DelayCondition};
    tr.NominalDelayMs  = p.NominalDelayMs(tr.DelayCondition);
    tr.DelayFrames     = p.DelayFrames(tr.DelayCondition);
    tr.ScheduledDelayMs = p.DelayActualMs(tr.DelayCondition);
    tr.Congruent       = rows(t, 3);
    if tr.Congruent
        tr.Congruency = 'congruent';
    else
        tr.Congruency = 'incongruent';
    end

    % Trial t begins wherever attention ended on trial t-1. A hold leaves
    % that position unchanged; a shift makes the opposite side the new end
    % position and therefore the start of the following trial.
    tr.InitialLocation = currentAttendedLocation; % 1=left, 2=right
    if tr.TrialTypeCode == 1
        tr.TargetLocation = 3 - tr.InitialLocation;
    else
        tr.TargetLocation = tr.InitialLocation;
    end
    tr.EndLocation = tr.TargetLocation;
    currentAttendedLocation = tr.EndLocation;
    tr.DistractorLocation = 3 - tr.TargetLocation;

    tr.TargetDirection = targetDirections(t); % 1=left, 2=right
    if tr.Congruent
        tr.DistractorDirection = tr.TargetDirection;
    else
        tr.DistractorDirection = 3 - tr.TargetDirection;
    end
    tr.NeutralDirection = neutralDirections(t); % 3=up, 4=down

    [tr.AttendedArray, tr.UnattendedArray] = ...
        makeLetterArrays(tr.TrialTypeCode);
    trials(t) = tr;
end


function cellCounts = balancedFactorCellCounts(nTrials, nDelays)
% Allocate trials over nDelays x 2 congruency cells. All candidate cells
% differ by at most one; among those allocations, choose one with the most
% even delay and congruency margins. Ties are randomized.
nCells = nDelays * 2;
baseCount = floor(nTrials / nCells);
nExtra = mod(nTrials, nCells);
cellCounts = ones(1, nCells) * baseCount;
if nExtra == 0
    return;
end

candidateExtras = nchoosek(1:nCells, nExtra);
scores = zeros(size(candidateExtras, 1), 2);
for candidate = 1:size(candidateExtras, 1)
    candidateCounts = cellCounts;
    candidateCounts(candidateExtras(candidate, :)) = ...
        candidateCounts(candidateExtras(candidate, :)) + 1;
    countMatrix = reshape(candidateCounts, 2, nDelays);
    delayMargins = sum(countMatrix, 1);
    congruencyMargins = sum(countMatrix, 2);
    scores(candidate, 1) = max(delayMargins) - min(delayMargins);
    scores(candidate, 2) = max(congruencyMargins) - min(congruencyMargins);
end

bestDelayScore = min(scores(:, 1));
bestCandidates = find(scores(:, 1) == bestDelayScore);
bestCongruencyScore = min(scores(bestCandidates, 2));
bestCandidates = bestCandidates( ...
    scores(bestCandidates, 2) == bestCongruencyScore);
selectedCandidate = bestCandidates(randi(numel(bestCandidates)));
cellCounts(candidateExtras(selectedCandidate, :)) = ...
    cellCounts(candidateExtras(selectedCandidate, :)) + 1;
end


function values = balancedBinary(n)
% Return a shuffled vector of 1s and 2s, balanced to within one trial.
nEach = floor(n / 2);
values = [ones(1, nEach), 2 * ones(1, nEach)];
if mod(n, 2) == 1
    values(end+1) = randi(2);
end
values = values(randperm(n));
end


function values = balancedWithinCells(rows)
% Balance a binary nuisance factor within Trial Type x Delay x Congruency.
[~, ~, groupIndex] = unique(rows(:, 1:3), 'rows');
nGroups = max(groupIndex);
groupSizes = accumarray(groupIndex, 1);
nOddGroups = sum(mod(groupSizes, 2) == 1);
extraSides = balancedBinary(nOddGroups);
extraIndex = 1;
values = zeros(1, size(rows, 1));

for group = 1:nGroups
    indices = find(groupIndex == group);
    n = numel(indices);
    nEach = floor(n / 2);
    cellValues = [ones(1, nEach), 2 * ones(1, nEach)];
    if mod(n, 2) == 1
        cellValues(end+1) = extraSides(extraIndex);
        extraIndex = extraIndex + 1;
    end
    values(indices) = cellValues(randperm(n));
end
end


function [attendedArray, unattendedArray] = makeLetterArrays(trialTypeCode)

fillerLetters = 'ABDEFGIJKLMNOPQRTUVWXYZ';
if trialTypeCode == 1
    criticalLetter = 'S';
else
    criticalLetter = 'H';
end

criticalPosition = randi(3);
attendedArray = fillerLetters(randi(numel(fillerLetters), 1, 3));
attendedArray(criticalPosition) = criticalLetter;
unattendedArray = fillerLetters(randi(numel(fillerLetters), 1, 3));
end


function [result, quitRequested] = runTrial(window, p, tr, blockNumber, trialNumber)
result = emptyTrialResult();
quitRequested = false;
rapidQuitDetected(p, true);

% Copy all planned factors into the trial-level result.
result.Subject            = p.Subject;
result.Version            = p.Version;
result.Block              = blockNumber;
result.BlockTypeCode      = tr.BlockTypeCode;
result.BlockType          = tr.BlockType;
result.BlockShiftProbability = tr.BlockShiftProbability;
result.Trial              = trialNumber;
result.TrialTypeCode      = tr.TrialTypeCode;
result.TrialType          = tr.TrialType;
result.Congruent          = tr.Congruent;
result.Congruency         = tr.Congruency;
result.DelayCondition     = tr.DelayCondition;
result.DelayLabel         = tr.DelayLabel;
result.NominalDelayMs     = tr.NominalDelayMs;
result.DelayFrames        = tr.DelayFrames;
result.ScheduledDelayMs   = tr.ScheduledDelayMs;
result.InitialLocation    = tr.InitialLocation;
result.EndLocation        = tr.EndLocation;
result.TargetLocation     = tr.TargetLocation;
result.DistractorLocation = tr.DistractorLocation;
result.TargetDirection    = directionName(tr.TargetDirection);
result.DistractorDirection = directionName(tr.DistractorDirection);
result.NeutralDirection   = directionName(tr.NeutralDirection);
result.AttendedArray      = tr.AttendedArray;
result.UnattendedArray    = tr.UnattendedArray;

% Initial fixation and placeholders.
drawBaseDisplay(window, p, 0);
[fixVBL, fixOnset] = Screen('Flip', window);
result.FixationOnset = fixOnset;

% Spatial cue: thicken the initially attended placeholder for 250 ms.
drawBaseDisplay(window, p, tr.InitialLocation);
[~, spatialCueOnset, ~, result.SpatialCueMissed] = Screen('Flip', ...
    window, fixVBL + p.InitialFixationSeconds - p.slack);
result.SpatialCueOnset = spatialCueOnset;

drawBaseDisplay(window, p, 0);
[~, spatialCueOffset, ~, result.SpatialCueOffsetMissed] = Screen('Flip', ...
    window, spatialCueOnset + p.SpatialCueSeconds - p.slack);
result.SpatialCueOffset = spatialCueOffset;

% The random interval is measured from spatial-cue offset.
postCueInterval = p.PostSpatialCueRangeSeconds(1) + rand * ...
    diff(p.PostSpatialCueRangeSeconds);
result.PostSpatialCueIntervalMs = postCueInterval * 1000;
shiftCueDeadline = spatialCueOffset + postCueInterval;

% From this onset onward the target is response-effective and the
% task-irrelevant Landolt C is response-neutral. The letter arrays are
% always drawn and remain unchanged through every following display.
drawStimulusDisplay(window, p, tr, false, false);

KbQueueFlush(p.KeyboardIndex);
KbQueueStart(p.KeyboardIndex);
[result.ShiftCueVBL, result.ShiftCueOnset, ~, ...
    result.ShiftCueMissed] = Screen('Flip', window, ...
    shiftCueDeadline - p.slack);

flashDue = result.ShiftCueOnset + tr.DelayFrames * p.ifi;
responseDeadline = result.ShiftCueOnset + p.ResponseDeadlineSeconds;
result.ScheduledFlashOnset = flashDue;
result.ResponseDeadline = responseDeadline;

% Flash is never cancelled by an early response. At flash onset, the
% distractor becomes response-effective and gray; the letter arrays remain
% exactly the same. The gray C lasts for the configured number of frames.
drawStimulusDisplay(window, p, tr, true, true);
[~, result.ActualFlashOnset, ~, result.FlashOnsetMissed] = ...
    Screen('Flip', window, flashDue - p.slack);
result.FlashPresented = true;
result.ActualFlashDelayMs = ...
    (result.ActualFlashOnset - result.ShiftCueOnset) * 1000;

flashOffsetDue = result.ActualFlashOnset + ...
    p.FlashDurationFrames * p.ifi;
drawStimulusDisplay(window, p, tr, true, false);
[~, result.FlashOffsetOnset, ~, result.FlashOffsetMissed] = ...
    Screen('Flip', window, flashOffsetDue - p.slack);

% Check the response queue only after the obligatory flash. A response made
% before the flash is still retained with its original timestamp and RT.
[responseCode, responseTime] = readQueuedResponse( ...
    p, result.ShiftCueOnset, responseDeadline);
if responseCode == 0 && GetSecs < responseDeadline
    [responseCode, responseTime] = pollForResponse( ...
        p, result.ShiftCueOnset, responseDeadline, responseDeadline);
end
timedOut = responseCode == 0;

KbQueueStop(p.KeyboardIndex);

result.TimedOut = timedOut;
if responseCode == p.Key.Escape
    % Triple-ESC is a task-level abort, not a trial response.
    result.ResponseKey = 'task-abort';
    result.ResponseDirection = '';
    result.Accuracy = NaN;
    quitRequested = true;
elseif responseCode ~= 0
    result.ResponseTime = responseTime;
    result.RT = responseTime - result.ShiftCueOnset;

    if responseCode == p.Key.Z
        result.ResponseKey = 'z';
        result.ResponseDirection = 'left';
        result.Accuracy = double(tr.TargetDirection == 1);
    elseif responseCode == p.Key.M
        result.ResponseKey = 'm';
        result.ResponseDirection = 'right';
        result.Accuracy = double(tr.TargetDirection == 2);
    end

end

if timedOut
    result.ResponseKey = 'none';
    result.ResponseDirection = '';
    result.Accuracy = 0;
end

fprintf(['Block %d Trial %02d | %-5s | %-11s | %-8s | ' ...
    '%-7s | RT '], blockNumber, trialNumber, tr.TrialType, ...
    tr.BlockType, tr.Congruency, tr.DelayLabel);
if isnan(result.RT)
    fprintf('NA');
else
    fprintf('%.0f ms', result.RT * 1000);
end
fprintf(' | flash=%d | acc=', result.FlashPresented);
if isnan(result.Accuracy)
    fprintf('NA\n');
else
    fprintf('%d\n', result.Accuracy);
end

% Remove the trial display, then hold the fixation/placeholders for the
% configurable inter-trial interval. A valid rapid triple-ESC still works
% during this interval.
drawBaseDisplay(window, p, 0);
[~, interTrialOnset] = Screen('Flip', window);
KbQueueFlush(p.KeyboardIndex);
if ~quitRequested
    quitRequested = waitInterTrialInterval(p, interTrialOnset);
end
end


function [responseCode, responseTime] = pollForResponse(p, minTime, stopTime, maxTime)
responseCode = 0;
responseTime = NaN;
while GetSecs < stopTime
    [quitNow, quitTime] = rapidQuitDetected(p, false);
    if quitNow
        responseCode = p.Key.Escape;
        responseTime = quitTime;
        return;
    end
    [responseCode, responseTime] = readQueuedResponse(p, minTime, maxTime);
    if responseCode ~= 0
        return;
    end
    WaitSecs('YieldSecs', 0.001);
end
[quitNow, quitTime] = rapidQuitDetected(p, false);
if quitNow
    responseCode = p.Key.Escape;
    responseTime = quitTime;
    return;
end
[responseCode, responseTime] = readQueuedResponse(p, minTime, maxTime);
end


function [responseCode, responseTime] = readQueuedResponse(p, minTime, maxTime)
responseCode = 0;
responseTime = NaN;
[responded, firstPress] = KbQueueCheck(p.KeyboardIndex);
if ~responded
    return;
end

allowedCodes = [p.Key.Z, p.Key.M];
pressTimes = firstPress(allowedCodes);
isEligible = pressTimes >= minTime & pressTimes <= maxTime;
if any(isEligible)
    eligibleIndices = find(isEligible);
    [responseTime, relativeIndex] = min(pressTimes(eligibleIndices));
    responseCode = allowedCodes(eligibleIndices(relativeIndex));
end
end


function [quitDetected, detectionTime] = rapidQuitDetected(p, resetState)
% A held ESCAPE counts only once. Three distinct ESCAPE down-events are required,
% with no more than QuitMaxInterPressSeconds between adjacent presses.
persistent escapePressCount lastEscapePressTime escapeWasDown activeKeyboardIndex

if resetState || isempty(activeKeyboardIndex) || ...
        activeKeyboardIndex ~= p.KeyboardIndex
    escapePressCount = 0;
    lastEscapePressTime = NaN;
    escapeWasDown = false;
    activeKeyboardIndex = p.KeyboardIndex;
    quitDetected = false;
    detectionTime = NaN;
    return;
end

quitDetected = false;
detectionTime = NaN;
[~, checkTime, keyCode] = KbCheck(p.KeyboardIndex);
escapeIsDown = keyCode(p.Key.Escape);

if escapeIsDown && ~escapeWasDown
    if isnan(lastEscapePressTime) || ...
            checkTime - lastEscapePressTime > p.QuitMaxInterPressSeconds
        escapePressCount = 1;
    else
        escapePressCount = escapePressCount + 1;
    end
    lastEscapePressTime = checkTime;

    if escapePressCount >= p.QuitPressCount
        quitDetected = true;
        detectionTime = checkTime;
        escapePressCount = 0;
        lastEscapePressTime = NaN;
    end
end
escapeWasDown = escapeIsDown;
end


function quitRequested = waitInterTrialInterval(p, intervalStart)
quitRequested = false;
intervalEnd = intervalStart + p.InterTrialIntervalSeconds;
while GetSecs < intervalEnd
    [quitNow, ~] = rapidQuitDetected(p, false);
    if quitNow
        quitRequested = true;
        return;
    end
    WaitSecs('YieldSecs', 0.001);
end
end


function drawBaseDisplay(window, p, cuedSide)
Screen('FillRect', window, p.BackgroundColor);
for side = 1:2
    lineWidth = p.PlaceholderLinePx;
    if side == cuedSide
        lineWidth = p.SpatialCueLinePx;
    end
    Screen('FrameOval', window, p.ForegroundColor, ...
        p.PlaceholderRects(side, :), lineWidth);
end
drawFixation(window, p);
end


function drawStimulusDisplay(window, p, tr, distractorEffective, flashVisible)
drawBaseDisplay(window, p, 0);

% Letter arrays are unconditional: target onset, flash, post-flash, and the
% remaining response window all use the same arrays in the same color.
if tr.InitialLocation == 1
    leftArray  = tr.AttendedArray;
    rightArray = tr.UnattendedArray;
else
    leftArray  = tr.UnattendedArray;
    rightArray = tr.AttendedArray;
end
Screen('TextSize', window, p.ArrayTextSizePx);
drawCenteredTextAt(window, leftArray, p.LocationXY(1, 1), ...
    p.LocationXY(1, 2) + p.ArrayYOffsetPx, p.ForegroundColor);
drawCenteredTextAt(window, rightArray, p.LocationXY(2, 1), ...
    p.LocationXY(2, 2) + p.ArrayYOffsetPx, p.ForegroundColor);

targetXY = p.LocationXY(tr.TargetLocation, :) + [0, p.LandoltYOffsetPx];
distractorXY = p.LocationXY(tr.DistractorLocation, :) + [0, p.LandoltYOffsetPx];
drawLandoltC(window, p, targetXY, tr.TargetDirection, p.ForegroundColor);
if distractorEffective
    distractorDirection = tr.DistractorDirection;
else
    distractorDirection = tr.NeutralDirection;
end
if flashVisible
    distractorColor = p.FlashLandoltColor;
else
    distractorColor = p.ForegroundColor;
end
drawLandoltC(window, p, distractorXY, distractorDirection, distractorColor);
end


function drawLandoltC(window, p, centerXY, directionCode, landoltColor)
outerRect = CenterRectOnPointd( ...
    [0, 0, 2*p.LandoltOuterRadiusPx, 2*p.LandoltOuterRadiusPx], ...
    centerXY(1), centerXY(2));
innerRect = CenterRectOnPointd( ...
    [0, 0, 2*p.LandoltInnerRadiusPx, 2*p.LandoltInnerRadiusPx], ...
    centerXY(1), centerXY(2));
Screen('FillOval', window, landoltColor, outerRect);
Screen('FillOval', window, p.BackgroundColor, innerRect);

cx = centerXY(1);
cy = centerXY(2);
rOuter = p.LandoltOuterRadiusPx + 1;
rInner = p.LandoltInnerRadiusPx - 1;
g = p.LandoltGapHalfPx;
switch directionCode
    case 1 % left-facing: gap opens left
        gapRect = [cx-rOuter, cy-g, cx-rInner, cy+g];
    case 2 % right-facing: gap opens right
        gapRect = [cx+rInner, cy-g, cx+rOuter, cy+g];
    case 3 % up-facing
        gapRect = [cx-g, cy-rOuter, cx+g, cy-rInner];
    case 4 % down-facing
        gapRect = [cx-g, cy+rInner, cx+g, cy+rOuter];
    otherwise
        error('Unknown Landolt-C direction code.');
end
Screen('FillRect', window, p.BackgroundColor, gapRect);
end


function drawFixation(window, p)
Screen('TextSize', window, 34);
drawCenteredTextAt(window, '+', p.CenterXY(1), p.CenterXY(2), ...
    p.ForegroundColor);
end


function drawCenteredTextAt(window, textString, cx, cy, color)
bounds = Screen('TextBounds', window, textString);
x = cx - RectWidth(bounds) / 2;
y = cy - RectHeight(bounds) / 2;
Screen('DrawText', window, textString, x, y, color);
end


function drawBlockStart(window, p, blockNumber)
Screen('FillRect', window, p.BackgroundColor);
Screen('TextSize', window, p.InstructionTextSize);
message = sprintf(['Block %d of %d\n\n' ...
    'Use the letter array at the cued location:\n' ...
    'S = shift attention, H = hold attention.\n\n' ...
    'Report the target Landolt-C gap:\n' ...
    'Z = left, M = right.\n' ...
    'To end early, press ESCAPE three times rapidly.\n\n' ...
    'Press SPACE to begin.'], blockNumber, p.NumBlocks);
DrawFormattedText(window, message, 'center', 'center', p.ForegroundColor, 70);
Screen('Flip', window);
end


function drawBreakScreen(window, p, blockNumber, accuracy)
Screen('FillRect', window, p.BackgroundColor);
Screen('TextSize', window, p.InstructionTextSize);
message = sprintf(['Block %d complete.\n\nAccuracy: %.1f%%\n\n' ...
    'Take a break. Press SPACE when ready to continue.'], ...
    blockNumber, accuracy);
DrawFormattedText(window, message, 'center', 'center', p.ForegroundColor, 70);
Screen('Flip', window);
end


function drawEndScreen(window, p)
Screen('FillRect', window, p.BackgroundColor);
Screen('TextSize', window, p.InstructionTextSize);
if p.CompletedSuccessfully
    message = sprintf('The experiment is complete.\n\nThank you!');
else
    message = sprintf(['The experiment ended early.\n\n' ...
        'Available data were saved.']);
end
DrawFormattedText(window, message, 'center', 'center', p.ForegroundColor, 70);
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
    if isDown
        if keyCode(p.Key.Space)
            choice = 'space';
        end
        while KbCheck(p.KeyboardIndex)
            WaitSecs('YieldSecs', 0.01);
        end
    else
        WaitSecs('YieldSecs', 0.01);
    end
end
end


function accuracyPercent = calculateAccuracy(results)
values = [results.Accuracy];
values = values(~isnan(values));
if isempty(values)
    accuracyPercent = NaN;
else
    accuracyPercent = mean(values) * 100;
end
end


function saveSession(p)
save([p.OutputBase '.mat'], 'p', '-v7');
if isfield(p, 'CompletedTrials') && p.CompletedTrials > 0
    completed = p.Results(1:p.CompletedTrials);
    trialTable = struct2table(completed);
    writetable(trialTable, [p.OutputBase '_trials.csv']);
end
end


function name = directionName(code)
names = {'left', 'right', 'up', 'down'};
name = names{code};
end


function tr = emptyPlannedTrial
tr = struct( ...
    'BlockTypeCode', '', ...
    'BlockType', '', ...
    'BlockShiftProbability', NaN, ...
    'TrialTypeCode', NaN, ...
    'TrialType', '', ...
    'DelayCondition', NaN, ...
    'DelayLabel', '', ...
    'NominalDelayMs', NaN, ...
    'DelayFrames', NaN, ...
    'ScheduledDelayMs', NaN, ...
    'Congruent', NaN, ...
    'Congruency', '', ...
    'InitialLocation', NaN, ...
    'EndLocation', NaN, ...
    'TargetLocation', NaN, ...
    'DistractorLocation', NaN, ...
    'TargetDirection', NaN, ...
    'DistractorDirection', NaN, ...
    'NeutralDirection', NaN, ...
    'AttendedArray', '', ...
    'UnattendedArray', '');
end


function result = emptyTrialResult
result = struct( ...
    'Subject', NaN, ...
    'Version', NaN, ...
    'Block', NaN, ...
    'BlockTypeCode', '', ...
    'BlockType', '', ...
    'BlockShiftProbability', NaN, ...
    'Trial', NaN, ...
    'TrialTypeCode', NaN, ...
    'TrialType', '', ...
    'Congruent', NaN, ...
    'Congruency', '', ...
    'DelayCondition', NaN, ...
    'DelayLabel', '', ...
    'NominalDelayMs', NaN, ...
    'DelayFrames', NaN, ...
    'ScheduledDelayMs', NaN, ...
    'InitialLocation', NaN, ...
    'EndLocation', NaN, ...
    'TargetLocation', NaN, ...
    'DistractorLocation', NaN, ...
    'TargetDirection', '', ...
    'DistractorDirection', '', ...
    'NeutralDirection', '', ...
    'AttendedArray', '', ...
    'UnattendedArray', '', ...
    'FixationOnset', NaN, ...
    'SpatialCueOnset', NaN, ...
    'SpatialCueOffset', NaN, ...
    'SpatialCueMissed', NaN, ...
    'SpatialCueOffsetMissed', NaN, ...
    'PostSpatialCueIntervalMs', NaN, ...
    'ShiftCueVBL', NaN, ...
    'ShiftCueOnset', NaN, ...
    'ShiftCueMissed', NaN, ...
    'ScheduledFlashOnset', NaN, ...
    'ActualFlashOnset', NaN, ...
    'ActualFlashDelayMs', NaN, ...
    'FlashOnsetMissed', NaN, ...
    'FlashOffsetOnset', NaN, ...
    'FlashOffsetMissed', NaN, ...
    'FlashPresented', false, ...
    'ResponseDeadline', NaN, ...
    'ResponseTime', NaN, ...
    'ResponseKey', '', ...
    'ResponseDirection', '', ...
    'RT', NaN, ...
    'Accuracy', NaN, ...
    'TimedOut', false);
end
