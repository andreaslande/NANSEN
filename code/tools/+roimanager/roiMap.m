classdef roiMap < handle
    
    % TODO:
    %  *[ ] Have access to signal extraction settings from roimanager.
    %   [ ] Can i find another way than adding userdata everytime a roi is
    %       created or modified....???
    %   [ ] Rename to roiFovMap?
    
    properties (Access = public)
        roiGroup
        roiMaskAll = [];            % A logical mask where all rois are added.
        defaultColor = ones(1,3)*0.8; % Add color picker to settings...
        
        lineWidth = 1 % Todo: implement this and make it adjustable from settings
        %roiArray (property of roigroup)
        %roiCount        % A counter for the number of rois that have been drawn
        
        Visible matlab.lang.OnOffSwitchState = true
    end
    
    
    properties (Access = public)
        displayApp % aka. app aka. hViewer...
        hRoimanager
        hAxes
        %smallRoiDisplay
    end
    
    
    properties (Access = public)
        roiOutlineVisible = true % Todo: make set method, so that this is updated when value is changed...
        roiLabelVisible = false
        neuropilMaskVisible = false % Todo: make set method, so that this is updated when value is changed...
    end
    
        
    properties (Transient, Access=private)
        roisChangedListener event.listener %Listener to changes on roi data
        roiSelectionChangedListener event.listener %Listener to changes on roi selection
        classificationChangedListener event.listener
    end %properties
    
    
    properties (Access = private) % Properties related to how to display rois.
        
        % Different roi classes, their abbreviations, and color for plots.
        roiClasses = {'Neuronal Soma', 'Neuronal Dendrite', 'Neuronal Axon', 'Neuropill','Astrocyte Soma','Astrocyte Endfoot','Astrocyte Process','Gliopill', 'Artery', 'Vein', 'Capillary'};
        roiTags = {'NS', 'ND', 'NA','Np','AS', 'AE', 'AP','Gp','Ar','Ve','Ca'}
        roiColors = {'Red', 'Green', [.96 .65 .027], [.75 .5 0], [.96 .45 .027], [0.016 .61 .51], [.63 .90 .02], [.067 .48 0], [.24 .09 .66], [.43 .051 .64], [.76, .02 .47]}
    
    end
    
    
    % Properties with graphics handles
    properties (Access = private)

        roiPlotHandles = {}     % A list of plot handles for all finished rois
        roiTextHandles = {}     % A list of text handles for all finished rois
        roiLinkHandles = {}     % A list of plot handles for all links between rois
        
        roiLinePos = {}         % A list of coordinates for roi outlines
        roiTextPos = {}         % A list of coordinates roi text labels.
        
    end
    
    
    % Properties for keeping temporary values.
    properties (Access = private)
    
        roiDisplacement = 0;            % Temporary "keeper" of roi displacement if rois are moved

        roiIndexMap = [];           % An array where the value at each pixel/coordinate is the index of the roi occupying that pixel/coordinate
        
        selectedRois     % Should it be property of this class?               % Numbers of the selected/active rois %  
        unselectedRois   % Should it be property of this class? 
        
    end
    
    
    events
        mapUpdated
    end
    
    
    methods (Access = public) % Constructor
        
        
        function obj = roiMap(app, hAxes, roiGroup)
        
            
            obj.displayApp = app;
            obj.hAxes = hAxes;
            
            if nargin < 3 || isempty(roiGroup)
                obj.roiGroup = roimanager.roiGroup();
            else
                obj.roiGroup = roiGroup;
            end
            
            obj.roisChangedListener = event.listener(obj.roiGroup, ...
                'roisChanged', @(s, e) onRoiGroupChanged(obj, e));
            
            obj.roiSelectionChangedListener = event.listener(obj.roiGroup, ...
                'roiSelectionChanged', @(s, e) onRoiSelectionChanged(obj, e));
           
            obj.classificationChangedListener = event.listener(obj.roiGroup, ...
                'classificationChanged', @(s, e) onRoiClassificationChanged(obj, e));
            
        end
        
        function delete(obj)
            if ~isempty(obj.roiPlotHandles) && isvalid(obj.roiPlotHandles(1))
                delete(obj.roiPlotHandles)
                delete(obj.roiTextHandles)
                delete(obj.roiLinkHandles)
            end
        end
        
    end
    
    methods (Access = private)
          
        function onRoiGroupChanged(obj, evt)
            % Triggered on existing roiGroup events
            
            % Todo: also update text label. 
            % (Maybe text label is not implemented)
            
            
            % Take action for this EventType
            switch lower(evt.eventType)
                
                case {'initialize', 'append', 'insert'}
                    
                    obj.plotRoi(evt.roiArray, evt.roiIndices, evt.eventType)
                    obj.updateRoiMaskAll(evt.roiIndices, evt.eventType)
                    obj.updateRoiIndexMap()
                    
                case {'modify', 'reshape'}
                    for i = evt.roiIndices
                        obj.updateRoiPlot(i)
                    end
                    obj.updateLinkPlot(evt.roiIndices)

                    obj.updateRoiMaskAll(evt.roiIndices, evt.eventType)
                    obj.updateRoiIndexMap()
                    
                case 'remove'
                    delete(obj.roiPlotHandles(evt.roiIndices))
                    delete(obj.roiTextHandles(evt.roiIndices))
                    delete(obj.roiLinkHandles(evt.roiIndices))

                    obj.roiPlotHandles(evt.roiIndices) = [];
                    obj.roiTextHandles(evt.roiIndices) = [];
                    obj.roiLinkHandles(evt.roiIndices) = [];

                    obj.roiLinePos(evt.roiIndices, :) = [];
                    obj.roiTextPos(evt.roiIndices) = [];
                    obj.updateRoiMaskAll(evt.roiIndices, 'remove') 
                    
                    % TODO: Should this be done before or after i delete
                    % the rois from roiArray in roiGroup. I could pass
                    % roiindices here.
                    obj.updateRoiIndexMap()
                    
                case {'connect', 'relink'}
                    obj.updateLinkPlot(evt.roiIndices, evt.eventType)

                otherwise
                    
                    % Throw a warning, then redraw just to be safe
                    warning('onRoiGroupChanged:UnhandledEvent',...
                        'Unhandled event type: %s',evt.EventType);
                    
            end %switch
            
            obj.notify('mapUpdated')
            
        end %function
        
        function onNeuropilMaskVisibleChanged(obj)
            
            if obj.neuropilMaskVisible
                for i = obj.selectedRois
                    obj.addNeuropilPatch(i)
                end
            else
                for i = obj.selectedRois
                    obj.removeNeuropilPatch(i)
                end
            end
            
        end
        
        function onVisibleChanged(obj)
            
            switch obj.Visible
                case 'on'
                    if obj.roiOutlineVisible
                        set(obj.roiPlotHandles, 'Visible', 'on')
                    else
                        set(obj.roiPlotHandles, 'Visible', 'off')
                    end
                    
                    
                case 'off'
                    set(obj.roiPlotHandles, 'Visible', 'off')
            end
            
        end
        
    end %methods
    
    methods % Set / get
        function set.neuropilMaskVisible(obj, newValue)
            
            obj.neuropilMaskVisible = newValue;
            obj.onNeuropilMaskVisibleChanged()
        end
        
        function set.Visible(obj, newValue)
            obj.Visible = newValue;
            obj.onVisibleChanged()
        end
        
    end
    
    methods
        
% % % % Methods for plotting rois and modifying the plots
        
        function plotRoi(obj, roiArray, ind, mode)
        %plotRoi Plot the roi in the axes of the display app.
        %
        %   obj.plotRoi(roiArray, ind, mode) plots the rois in ROIARRAY in
        %   the display app. If specified, IND is the indices of where to
        %   add rois in the graphics handles and mode is either append or
        %   insert.
        
        %   Options for mode: 
        %       append (default) : Append rois to the end
        %       insert           : Insert rois at index locations specified
        %                          by ind
        
        
            % Set default values of input arguments
            if nargin < 4; mode = 'append'; end
            
            if nargin < 3
                ind = obj.roiGroup.roiCount - fliplr(1:numel(roiArray)) + 1;
            end
            
            
            % Initialize Plot/Text handles and position cell arrays
            if isempty(obj.roiPlotHandles)
                obj.roiPlotHandles = gobjects(0);
                obj.roiTextHandles = gobjects(0);
                obj.roiLinkHandles = gobjects(0);
            end   
            
            
            % Preallocate arrays for different features.
            nRois = numel(roiArray);
            
            colorCellArray = cell(nRois, 1);
            roiBoundaryCellArray = cell(2, nRois);
            centerPosArray = zeros(nRois, 3);

            % Collect boundaries for all rois in a cell array
            for roiNo = 1:numel(roiArray)
                colorCellArray{roiNo} = obj.getRoiColor(roiArray(roiNo));
                centerPosArray(roiNo, :) = [roiArray(roiNo).center, 0];

                boundary = roiArray(roiNo).boundary{1};
                roiBoundaryCellArray{1, roiNo} = boundary(:,2); 
                roiBoundaryCellArray{2, roiNo} = boundary(:,1);
            end

            % Replace empty boundaries with nan value to get a plot
            % handle also for rois that are not defined...
            [i, j] = find(cellfun(@(a) isempty(a), roiBoundaryCellArray));
            roiBoundaryCellArray(i, j) = {nan};

            % Plot lines and add text objects for all rois
            %Use plot instead of line in order to plot all boundaries
            hLine = plot(obj.hAxes, roiBoundaryCellArray{:}, 'LineStyle', '-', 'Marker', 'None');
            hText = text(obj.hAxes, centerPosArray(:, 1), centerPosArray(:, 2), '');

            set(hLine, {'color'}, colorCellArray)
            set(hLine, 'HitTest', 'off')
            set(hLine, 'PickableParts', 'none')
            set(hLine, 'Tag', 'RoI')
            set(hLine, 'LineWidth', obj.lineWidth)

            set(hText, {'color'}, colorCellArray)
            set(hText, 'HitTest', 'off')
            set(hText, 'PickableParts', 'none')
            set(hText, 'HorizontalAlignment', 'center')
            set(hText, 'Tag', 'RoIlabel')

            
                    
            % Assemble text labels for the listbox
            tags = {roiArray.tag};
            nums = arrayfun(@(i) num2str(i, '%03d'), ind, 'uni', 0);
            % Set texthandles
            set(hText, {'String'}, strcat(tags, nums)');
            
            
            if ~obj.roiOutlineVisible
                set(hLine, 'Visible', 'off')
            end
            
            if ~obj.roiLabelVisible
                set(hText, 'Visible', 'off')
            end
            
            % Todo:
% % %             % Set visibility of text based on button "Show/Hide Tags"
% % %             if obj.settings.showTags
% % %                 set(hText, 'Visible', 'on')
% % %             else
% % %                 set(hText, 'Visible', 'off')
% % %             end

            % Plot links for all connected rois            
            
            
            % Collect links for all rois in a cell array
            hLink = plot(obj.hAxes, nan(2, nRois), 'LineStyle', '-', 'Marker', 'None', 'Color', ones(1,3)*0.8);
            set(hLink, 'HitTest', 'off')
            set(hLink, 'PickableParts', 'none')
            
            % NB: Ind is a row vector, so plot handles become a row
            % vector as well. hLine and hText are column vectors, thats
            % why I transpose before inserting into array.

            % Add to the end
            switch mode
                case {'append', 'initialize'}
                    obj.roiPlotHandles(ind) = hLine;
                    obj.roiTextHandles(ind) = hText;
                    obj.roiLinkHandles(ind) = hLink;
                case 'insert'
                    obj.roiPlotHandles = utility.insertIntoArray(obj.roiPlotHandles, hLine', ind);
                    obj.roiTextHandles = utility.insertIntoArray(obj.roiTextHandles, hText', ind);
                    obj.roiLinkHandles = utility.insertIntoArray(obj.roiLinkHandles, hLink', ind);
            end

            obj.updateLinkPlot(ind)
            
            % Add positions to position arrays
            % NB: Have to transpose roiBoundaryCellArray here.
            centerPosArray = arrayfun(@(i) centerPosArray(i,:), 1:nRois, 'uni', 0);
            switch mode
                case {'append', 'initialize'}
                    obj.roiLinePos(ind, :) = roiBoundaryCellArray';
                    obj.roiTextPos(ind, 1) = centerPosArray;
                case 'insert'
                    obj.roiLinePos = utility.insertIntoArray(obj.roiLinePos, roiBoundaryCellArray', ind, 1);
                    obj.roiTextPos = utility.insertIntoArray(obj.roiTextPos, centerPosArray', ind, 1);
            end
             
        end
        
        
        function shiftRoiPlot(obj, shift)
        % Shift Roi plots according to a shift [x, y, 0]
            % Get active roi
            
            xData = {obj.roiPlotHandles(obj.selectedRois).XData};
            yData = {obj.roiPlotHandles(obj.selectedRois).YData};
            
            % Calculate and update position 
            xData = cellfun(@(x) x+shift(1), xData, 'uni', 0);
            yData = cellfun(@(y) y+shift(2), yData, 'uni', 0);
            set(obj.roiPlotHandles(obj.selectedRois), {'XData'}, xData', {'YData'}, yData')

            % Shift text labels to new position, but only perform shift if 
            % they are visible. If not, they will be shifted when actual 
            % rois are moved.

% % %             if obj.settings.showTags
% % %                 textpos = {obj.roiTextHandles(obj.selectedRois).Position};
% % %                 textpos = cellfun(@(pos) pos + shift, textpos, 'uni', 0);
% % %                 set(obj.roiTextHandles(obj.selectedRois), {'Position'}, textpos')
% % %             end
            
%             drawnow;

            obj.shiftLinkPlot(shift)

        end
        
        
        function shiftLinkPlot(obj, shift)
            isPropEmpty = @(prop) arrayfun(@(roi) isempty(roi.(prop)), obj.roiGroup.roiArray);
            
            parentInd = find( ~isPropEmpty('connectedrois') );
            childInd = find( ~isPropEmpty('parentroi') );
            
            if isempty(parentInd) && isempty(childInd); return; end
            
            parentInd = intersect(parentInd, obj.selectedRois, 'stable');
            childInd = intersect(childInd, obj.selectedRois, 'stable');
            
            childUIds = cat(2, obj.roiGroup.roiArray(parentInd).connectedrois);
            childUIds = unique(childUIds);
            if ~isempty(childUIds)
                [~, childOfParentInd] = intersect({obj.roiGroup.roiArray.uid}, childUIds);
            else
                childOfParentInd = [];
            end
            
            % Calculate and update position for parents
            xData = {obj.roiLinkHandles(parentInd).XData};
            yData = {obj.roiLinkHandles(parentInd).YData};
                       
            xData = cellfun(@(x) x+shift(1), xData, 'uni', 0);
            yData = cellfun(@(y) y+shift(2), yData, 'uni', 0);
            set(obj.roiLinkHandles(parentInd), {'XData'}, xData', {'YData'}, yData')
            
            % Calculate and update position for children which parent is
            % not selected
            xData = {obj.roiLinkHandles(childInd).XData};
            yData = {obj.roiLinkHandles(childInd).YData};
            
            xData = cellfun(@(x) x+[0,shift(1)], xData, 'uni', 0);
            yData = cellfun(@(y) y+[0,shift(2)], yData, 'uni', 0);
            set(obj.roiLinkHandles(childInd), {'XData'}, xData', {'YData'}, yData')
            
            % Calculate and update position for children which parent is selected
            xData = {obj.roiLinkHandles(childOfParentInd).XData};
            yData = {obj.roiLinkHandles(childOfParentInd).YData};
            
            xData = cellfun(@(x) x+[shift(1),0], xData, 'uni', 0);
            yData = cellfun(@(y) y+[shift(2),0], yData, 'uni', 0);
            set(obj.roiLinkHandles(childOfParentInd), {'XData'}, xData', {'YData'}, yData')
            
        end
        
        
        function updateRoiPlot(obj, roiInd)
        % Replot the roi at idx in roiArray
        
        %TODO: Accept vector of roi indices.
            
            roi = obj.roiGroup.roiArray(roiInd);
            
            for j = 1:length(roi.boundary)
                if j == 1
                    boundary = roi.boundary{j};
                else
                    boundary = cat(1, boundary, [nan,nan], roi.boundary{j});
                end
            end
            
            boundary = roi.boundary{1};

            obj.roiPlotHandles(roiInd).XData = boundary(:, 2);
            obj.roiPlotHandles(roiInd).YData = boundary(:, 1);
            % Move roi label/tag to new center position
            set(obj.roiTextHandles(roiInd), 'Position', [roi.center, 0])

            
            obj.roiLinePos(roiInd, :) = {boundary(:, 2), boundary(:, 1)};
            % Move roi label/tag to new center position
            obj.roiTextPos(roiInd) = {[roi.center, 0]};
            
            
        end
        
        
        function updateLinkPlot(obj, roiInd, mode)
            
            if nargin == 3 && strcmp(mode, 'relink')
                nRois = numel(roiInd);
                delete(obj.roiLinkHandles)
                obj.roiLinkHandles = plot(obj.hAxes, nan(2, nRois), ...
                    'LineStyle', '-', 'Marker', 'None', 'Color', ones(1,3)*0.8, ...
                     'HitTest', 'off', 'PickableParts', 'none');
            end
            
            isPropEmpty = @(prop) arrayfun(@(roi) isempty(roi.(prop)), obj.roiGroup.roiArray);
            
            parentInd = find( ~isPropEmpty('connectedrois') );
            childInd = find( ~isPropEmpty('parentroi') );
            
            parentInd = intersect(parentInd, roiInd, 'stable');
            childInd = intersect(childInd, roiInd, 'stable');

            % Plot parent data
            parentData = cat(1, obj.roiGroup.roiArray(parentInd).center);
            parentData = num2cell(parentData);
            
            if ~isempty(parentInd)
                set(obj.roiLinkHandles(parentInd), {'XData'}, parentData(:,1),  {'YData'}, parentData(:,2), 'Marker', 'o', 'MarkerSize', 5)
            end
            roiUids = {obj.roiGroup.roiArray.uid};
            linkPosArray = cell(numel(childInd), 2);

            for i = 1:numel(childInd)
                ii = childInd(i);
                [~, iA] = intersect(roiUids, obj.roiGroup.roiArray(ii).parentroi);
                linkPosArray{i, 1} = [obj.roiGroup.roiArray(iA).center(1) obj.roiGroup.roiArray(ii).center(1)];
                linkPosArray{i, 2} = [obj.roiGroup.roiArray(iA).center(2) obj.roiGroup.roiArray(ii).center(2)];
            end
            
            if ~isempty(childInd)
                set(obj.roiLinkHandles(childInd), {'XData'}, linkPosArray(:,1),  {'YData'}, linkPosArray(:,2))
            end
        end
        

        function moveRoi(obj, shift)
        % Update RoI positions based on shift.
            
            % If rois have been dragged, some rois have been put in an 
            % unselectedRois list. These should be put back into the 
            % selectedRois list now.
            if ~isempty(obj.unselectedRois)
                obj.selectedRois = sort(horzcat(obj.selectedRois, obj.unselectedRois));
                obj.selectedRois = unique(obj.selectedRois);
                obj.unselectedRois = [];
            end
            
            % Get selected rois
            originalRois = obj.roiGroup.roiArray(obj.selectedRois);
            
            % Get new rois that are moved versions of original ones.
            newRois = originalRois;
            for i = 1:numel(originalRois)
                newRois(i) = originalRois(i).move(shift);
                newRois(i) = obj.addUserData(newRois(i));
            end
            
            obj.roiGroup.modifyRois(newRois, obj.selectedRois)
                       
        end

        
        function growRois(obj)
            
            % Get selected rois
            originalRois = obj.roiGroup.roiArray(obj.selectedRois);
            
            newRois = originalRois;
            for i = 1:numel(originalRois)
                newRois(i) = originalRois(i).grow(1); % Grow rois
            end
            
            obj.roiGroup.modifyRois(newRois, obj.selectedRois)
            
        end
        
        
        function shrinkRois(obj)
                        
            % Get selected rois
            originalRois = obj.roiGroup.roiArray(obj.selectedRois);
            
            newRois = originalRois;
            for i = 1:numel(originalRois)
                newRois(i) = originalRois(i).shrink(1); % Shrink rois
            end
            
            obj.roiGroup.modifyRois(newRois, obj.selectedRois)
            
        end
        
        
        function roiObj = addUserData(obj, roiObj)
            
            if true % classifier is open
                imArray = obj.displayApp.imageStack.getFrameSet('all');
                
                imSize = size(imArray);
                if imSize(end)<10; return; end

                % Todo: Can I get signal array from roimanager??? If it
                % exists???
                [im, stat] = roimanager.utilities.createRoiUserdata(roiObj, imArray);

                roiObj.enhancedImage = im.enhancedAverage;
                roiObj = setappdata(roiObj, 'roiClassification', 0);
                roiObj = setappdata(roiObj, 'roiImages', im);
                roiObj = setappdata(roiObj, 'roiStats', stat);
            end
            
        end
        
        % todo: move to roimanager
        function createPolygonRoi(obj, x, y, doReplace)

            if length(x) < 3 || length(y) < 3
                return
            end
            
            % Create a RoI object
            h = obj.displayApp.imHeight;
            w = obj.displayApp.imWidth;
            
            newRoi = RoI('Polygon', [x; y], [h, w]);
            newRoi = obj.addUserData(newRoi);
            %newRoi = obj.editRoiProperties(newRoi);
            
            obj.roiGroup.addRois(newRoi)
            
            obj.selectRois(obj.roiGroup.roiCount, 'normal')

            
        end
        
        % todo: move to roimanager
        function createCircularRoi(obj, x, y, r)
                      
            % Create a RoI object
            h = obj.displayApp.imHeight;
            w = obj.displayApp.imWidth;
            
            newRoi = RoI('Circle', [x, y, r], [h, w]);
            %newRoi = obj.editRoiProperties(newRoi);
            newRoi = obj.addUserData(newRoi);
            
            obj.roiGroup.addRois(newRoi)
            
            obj.selectRois(obj.roiGroup.roiCount, 'normal')
        end
        
        function createFreehandRoi(obj, x, y, thickness)
            
            if nargin < 4
                thickness = 3;
            end
            
            % Get image data from imviewer app.
            imSize = [obj.displayApp.imHeight,  obj.displayApp.imWidth];
            
            mask = false( imSize );
            
            ind = sub2ind(imSize, y, x);
            ind(isnan(ind)) = [];
            mask(ind) = true;

            mask = imdilate(mask, strel('disk', thickness));

            % Create a RoI object
            newRoi = RoI('Mask', mask, imSize);
            %newRoi = obj.editRoiProperties(newRoi);
            newRoi = obj.addUserData(newRoi);

            obj.roiGroup.addRois(newRoi)
            obj.selectRois(obj.roiGroup.roiCount, 'normal')
            
        end
        
        % todo: move to roimanager
        function newRoi = autodetectRoi(obj, x, y, r, autodetectionMode, doReplace)

            % Todo: This is not a roimap method. Move to roimanager.

            
            % Autodetection method: 
            %   Threshold current frame
            %   Threshold enhanced maximum projection
            %   Edgedetection current frame
            %   Edgedetection enhanced avg
            
            if nargin < 6; doReplace = false; end
            if nargin < 5; autodetectMethod = 'threshold'; end
            
            pad = 5; % TODO: Retrieve from settings/preferences
            
            % is this a flufinder task...
            
            % ad hoc for solution for setting an extended radius in mode 4
            rExtended = r(2);
            r = r(1);
            
            
            % Get image data from imviewer app.
            imSize = [obj.displayApp.imHeight,  obj.displayApp.imWidth];
            
            [S, L] = roimanager.imtools.getImageSubsetBounds(imSize, x, y, r, pad);
            
            imData = obj.displayApp.imageStack.getFrameSet('all');
            
            imChunk = roimanager.imtools.getPixelChunk(imData, S, L);
            
            
            % Get x- and y-coordinate for the image subset.
            x_ = x - S(1)+1; 
            y_ = y - S(2)+1;
            
            % Get signal from pixel chunk
            mask = roimanager.roitools.getCircularMask(size(imChunk), x_, y_, r);
            nFrames = size(imChunk, 3);
            
            mask_ = reshape(mask, 1, []);
            mask_ = mask_ ./ sum(mask_, 2); %mask_ = sparse(mask_);
            
            imChunk_ = double(reshape(imChunk, [], nFrames));
            signal = mask_ * imChunk_;

            
            % Get samples where activity is highest
            IND = roimanager.signalanalysis.findActiveSamplePoints(signal);
            if isempty(IND)
                [~, IND] = max(signal);
            end
            
            
            % Make image & Detect mask
          
            switch autodetectionMode
                case 1
                    %Todo: specify local center... This function should use local
                    %center, not assume to start in center of small image.
                    IM = mean(imChunk(:, :, IND), 3);            
                    [roiMask, ~] = roimanager.binarize.findRoiMaskFromImage(IM, [x, y], imSize);

                case 2
                    IM = max(imChunk(:, :, IND), [], 3);
                    roiMask_ = roimanager.roidetection.binarizeSomaImage(IM, 'InnerDiameter', 0, 'OuterDiameter', r*2);
                    roiMask = false(imSize);
                    roiMask(S(2):L(2), S(1):L(1)) = roiMask_;
                    
                case 3
                    
%                     IND = obj.displayApp.currentFrameNo;
%                     IM = imChunk(:, :, IND);
                    IM = roimanager.imtools.getPixelChunk(obj.displayApp.image, S, L);
                    IM = stack.makeuint8(single(IM));
                    roiMask_ = roimanager.roidetection.binarizeSomaImage(IM, 'InnerDiameter', 0, 'OuterDiameter', r*2, 'ExtentedRadius', r*4);
                    roiMask = false(imSize);
                    roiMask(S(2):L(2), S(1):L(1)) = roiMask_;
                case 4
                    
                    [S, L] = roimanager.imtools.getImageSubsetBounds(imSize, x, y, r, rExtended);
                    IM = roimanager.imtools.getPixelChunk(obj.displayApp.image, S, L);
                    IM = stack.makeuint8(single(IM));
                    roiMask_ = roimanager.roidetection.binarizeSomaImage(IM, 'InnerDiameter', 0, 'OuterDiameter', r*2);
                    roiMask = false(imSize);
                    roiMask(S(2):L(2), S(1):L(1)) = roiMask_;
                case 5
                    %Todo: specify local center... This function should use local
                    %center, not assume to start in center of small image.
                    IM = mean(imChunk(:, :, IND), 3);            
                    [roiMask, ~] = roimanager.binarize.findRoiMaskFromImage(IM, [x, y], imSize);
            end
            
% % %             if isempty(obj.smallRoiDisplay)
% % %                 obj.smallRoiDisplay = imviewer(IM);
% % %                 obj.smallRoiDisplay.resizeWindow([], [], 'down')
% % %                 obj.smallRoiDisplay.resizeWindow([], [], 'down')
% % %                 obj.smallRoiDisplay.resizeWindow([], [], 'down')
% % %                 obj.smallRoiDisplay.fig.Position(1:2) = [sum(obj.displayApp.fig.Position([1,3])), obj.displayApp.fig.Position(4)];
% % % 
% % %             else
% % %                 obj.smallRoiDisplay.image = IM;
% % %                 obj.smallRoiDisplay.updateImageDisplay()
% % %             end

             
            % Get roi settings from flufinder
            
            
            % run autodetect method from roi autodetection toolbox
            % roiMask = flufinder.autodetect(pixelChunk, refPoint, imSize, autodetectionMethod);
            
            
            if ~nargout
                
                newRoi = RoI('Mask', roiMask);

                if doReplace
                    i = obj.selectedRois;
                    newRoi = obj.addUserData(newRoi);
                    obj.roiGroup.modifyRois(newRoi, i)
                else
                    newRoi = obj.addUserData(newRoi);
                    obj.roiGroup.addRois(newRoi)
                end
                
                clear newRoi
                
            else
                newRoi = roiMask;
            end
            
            % add/reshape&replace roi
            
            % select roi            
        end
        
            
        function pObj = patchRoi(obj, mask, tag, color)
            % Patch a roi with potential holes.
            
            [boundary, ~, N, A] = bwboundaries(mask);
                        
            patchCoords =  {};
            
            % Loop through outer boundaries
            for k = 1:N
                
                enclosedBoundary = find(A(:, k));
                nEnclosed = numel(enclosedBoundary);
                
                % Add enclosed boundaries if any
                if nEnclosed > 0
                    boundaryLength = length(boundary{k});
                    splitIdx = round(linspace(1, boundaryLength, nEnclosed+1));
                    connectedBoundary = zeros(0, 2);
                    for l = 1:nEnclosed
                        connectedBoundary = vertcat(connectedBoundary, boundary{k}(splitIdx(l):splitIdx(l+1), :), flipud(boundary{enclosedBoundary(l)}));
                    end
                    patchCoords{end+1} = connectedBoundary;
                else
                    patchCoords{end+1} = boundary{k};
                end
                    
            end
            
            if nargin < 4
                colors = hsv(64);
                color = colors(randi(64), :);
            end
            
            pObj = gobjects(numel(patchCoords), 1);
            for i = 1:numel(patchCoords)
                pObj(i) = patch(patchCoords{i}(:, 2), patchCoords{i}(:, 1), color, 'facealpha', 0.2, 'EdgeColor', 'None', 'Parent', obj.hAxes, 'Tag', tag);
            end
            
            set(pObj,'HitTest', 'off', 'PickableParts', 'none')

        end
        
        function updateRoiMaskAll(obj, roiInd, action)
        %UPDATEROIMASKALL update a mask containing all rois in the FOV.
            
            
            if isempty(obj.roiMaskAll)
                obj.roiMaskAll = cat(3, obj.roiGroup.roiArray(:).mask);
                return
            end
            
            % TODO: How does this work for inserts?
            
            switch lower(action)
                case {'add', 'reshape', 'append', 'modify'}
                    obj.roiMaskAll(:,:,roiInd) = cat(3, obj.roiGroup.roiArray(roiInd).mask);
                case {'insert'}
                    dataToInsert =  cat(3, obj.roiGroup.roiArray(roiInd).mask);
                    obj.roiMaskAll = utility.insertIntoArray(obj.roiMaskAll, dataToInsert, roiInd, 3);

                case 'remove'
                    obj.roiMaskAll(:,:,roiInd) = [];
            end
            
        end
        
        function updateRoiIndexMap(obj, roiInd, action)
            
            % Todo: Make this smarter
            if isempty( obj.roiIndexMap )
                obj.roiIndexMap = zeros(size(obj.roiGroup.roiArray(1).mask));
            else
                obj.roiIndexMap(:) = 0;
            end
            
            

            for i = 1:obj.roiGroup.roiCount
                tmpMask = obj.roiGroup.roiArray(i).mask;
                obj.roiIndexMap(tmpMask) = i;
                
            end
            
% % %             switch lower(action)
% % %                 
% % %                 case 'add'
% % %                     for i = 1:obj.roiCount
% % %                         mask = obj.roiArray(roiInd(i)).mask;
% % %                         obj.roiIndMap(mask) = roiInd(i);
% % %                     end
% % %                     
% % %                 case 'remove'
% % %                     
% % %                     
% % %             end
            
            
        end
        
        
        function showRoiTextLabels(obj)
            set(obj.roiTextHandles, 'Visible', 'on')
        end
        
        function hideRoiTextLabels(obj)
            set(obj.roiTextHandles, 'Visible', 'off')
        end
        
        
        function showRoiOutlines(obj)
            set(obj.roiPlotHandles, 'Visible', 'on')
        end
        
        function hideRoiOutlines(obj)
            set(obj.roiPlotHandles, 'Visible', 'off')
        end
        
        function showRoiRelations(obj)
            set(obj.roiLinkHandles, 'Visible', 'on')
        end
        
        function hideRoiRelations(obj)
            set(obj.roiLinkHandles, 'Visible', 'off')
        end

% % % % Methods for showing neuropil
        
        function addNeuropilPatch(obj, i)
        % Patch surrounding neuropil
        
            %ch = obj.activeChannel;
        
            if obj.neuropilMaskVisible
                patchtag = sprintf('NpMask%03d', i);
                patches = findobj(obj.hAxes, 'Tag', patchtag);
                if ~isempty(patches)
                    return
                end
                
                % Todo: Get roi settings from somewhere...
                
                roiData = nansen.processing.roi.prepareRoiMasks(obj.roiGroup.roiArray, 'roiInd', i);
                npMask = roiData.Masks(:,:,2:end);
                  
% %                 % Find neuropil mask
% %                 switch obj.signalExtractionSettings.neuropilExtractionMethod.Selection
% %                     case 'Standard'
% %                         imageMask = logical(mean(obj.imgTseries{ch}(:,:,1:10), 3));
% %                         [~, npMask] = signalExtraction.standard.getMasks(obj.roiArray{ch}, i, imageMask, obj.roiSettings);
% %                     case 'Fissa'
% %                         npMask = signalExtraction.fissa.getMasks(obj.roiArray{ch}(i).mask);
% %                     otherwise
% %                         return
% %                 end
                   
                % Use patch roi function to patch the neuropil mask(s)
                for j = 1:size(npMask, 3)
                    obj.patchRoi(npMask(:, :, j), patchtag, 'w');
                end
            end
        end
        
        function removeNeuropilPatch(obj, i)
            
            if isequal(i, 'all')
                patchtag = sprintf('NpMask');
            else
                patchtag = sprintf('NpMask%03d', i);
            end
            patches = findobj(obj.hAxes, '-regexp', 'Tag', patchtag);
            if ~isempty(patches)
                delete(patches)
            end
            
        end
        
        
% % % % Methods for interaction with roi map
        function tf = isPointValid(obj, x, y)    
            tf = true;
        end

        function [wasInRoi, roiInd] = isPointInRoi(obj, x, y)
        %isPointInRoi Check if any roi is at a coordinate point.
        
            if isempty(obj.roiIndexMap)
                wasInRoi = false; roiInd = nan; return
            end
        
            roiIndAtPoint = obj.roiIndexMap(y, x);
            
            wasInRoi = roiIndAtPoint ~= 0;
            roiInd = roiIndAtPoint;
            if isequal(roiInd, 0); roiInd = nan; end
            
        end
        
        function wasInRoi = hittest(obj, src, event)
        %hittest Check if a mouseclick happened on a roi.
        
            %currentPoint = round( obj.hAxes.CurrentPoint(1, 1:2) );
            currentPoint = round(event.IntersectionPoint(1:2));
            
            
            [wasInRoi, roiInd] = obj.isPointInRoi(currentPoint(1), currentPoint(2));
            
            %roiInd
            
            hFig = ancestor(obj.hAxes, 'figure');
            obj.selectRois(roiInd, hFig.SelectionType, true)
            
            if ~nargout
                clear wasInRoi
            end

        end
        
        function roiInd = getRoisInRegion(obj, xBounds, yBounds)
        %getRoisInRegion Get rois within rectangular region
        
            xBounds = round(xBounds);
            yBounds = round(yBounds);
            
            [h,w] = size(obj.roiIndexMap);
            
            % Make sure bounds are within map.
            xBounds(1) = max([1, xBounds(1)]);
            xBounds(2) = min([w, xBounds(2)]);
            yBounds(1) = max([1, yBounds(1)]);
            yBounds(2) = min([h, yBounds(2)]);
            
            mask = false(size(obj.roiIndexMap));
            mask(yBounds(1):yBounds(2), xBounds(1):xBounds(2)) = true;
            
            roiInd = unique(obj.roiIndexMap(mask));
            roiInd(roiInd==0)=[];
            
            if iscolumn(roiInd); roiInd = transpose(roiInd); end
            
        end
        
        function onRoiSelectionChanged(obj, evtData)
        %onRoiSelectionChanged Takes care of selection of roi. 
        %
        %   Show roi as white in image on selection. Reset color on
        %   deselection
        
            roiIndices = evtData.roiIndices;
            if iscolumn(roiIndices)
                roiIndices = roiIndices';
                %disp('a') %Todo: debug, where does this become a col
                %vector
            end
            
            switch evtData.eventType
                case 'unselect'
                    
                    if ischar(roiIndices) && strcmp(roiIndices, 'all')
                        roiIndices = obj.selectedRois;
                        if isempty(obj.selectedRois); return; end
                    end
                    
                    obj.selectedRois = setdiff(obj.selectedRois, roiIndices);

                    colorCellArray = cell(numel(roiIndices), 1);
                    c = 1;
                    for i = roiIndices
                        colorCellArray{c} = obj.getRoiColor(obj.roiGroup.roiArray(i));
                        c = c+1;
                    end
                    newLineWidth = obj.lineWidth;
                    
                    if obj.neuropilMaskVisible
                        for i = roiIndices
                            obj.removeNeuropilPatch(i)
                        end
                    end
                    
                case 'select'
                    obj.selectedRois = union(obj.selectedRois, roiIndices);
                    
                    colorCellArray = repmat({'White'}, numel(roiIndices), 1);
                    newLineWidth = min([obj.lineWidth+2, 3]);
                    
                    if evtData.zoomOnRoi
                        obj.zoomInOnRoi(obj.selectedRois(end), true)
                    end
                    
                    if obj.neuropilMaskVisible
                        for i = roiIndices
                            obj.addNeuropilPatch(i)
                        end
                    end
            end
            
            
            % Change the color of roi outlines and text labels
            set(obj.roiPlotHandles(roiIndices), 'LineWidth', newLineWidth);
            set(obj.roiPlotHandles(roiIndices), {'color'}, colorCellArray);
            set(obj.roiTextHandles(roiIndices), {'color'}, colorCellArray); 

            
            if ~isempty(obj.selectedRois)
                obj.selectedRois = unique(obj.selectedRois, 'stable'); % The lazy way
            else
                obj.selectedRois = []; % setdiff creates an empty row vector, creates problems later...
            end
            
        end
        
        function onRoiClassificationChanged(obj, evtData)
            
            roiIndices = evtData.roiIndices;
            
            if true %strcmp(obj.settings.colorRoiBy, 'Validation')
                
                % Only recolor rois that are not selected.
                roiIndices = setdiff(roiIndices, obj.selectedRois);
                if isempty(roiIndices); return; end
                
                colorCellArray = cell(numel(roiIndices), 1);
                c = 1;
                for i = roiIndices
                    colorCellArray{c} = obj.getRoiColor(obj.roiGroup.roiArray(i));
                    c = c+1;
                end
                
                set(obj.roiPlotHandles(roiIndices), {'color'}, colorCellArray);
                set(obj.roiTextHandles(roiIndices), {'color'}, colorCellArray); 

            end
            
        end
        
        function selectRois(obj, roiIndices, selectionType, isMousePress)
        %selectRois
        %
        % This function can be activated by the following actions:
        %   Press a RoI in the image Display
        %   Press a RoI in the Listbox
        %   Tab shortcut key in undocking mode
        %   Cmd-a / Ctrl-a shortcut key
        %
        %   During a mouseclick, rois should be selected. If any rois
        %   should be deselected, this should happen when the mouse is
        %   released.
            
            if nargin < 4; isMousePress = false; end

            if isnan(roiIndices)
                wasInRoi = false;
            else
                wasInRoi = true;
            end
            
            obj.unselectedRois = []; % Make sure this is empty.
            
            switch selectionType
                
                case {'normal', 'open'} % RoiIndices should have length 1
                    
                    assert(numel(roiIndices)==1, 'Please report')
                    
                    % Reset selection of all unselected rois
                    deselectedRois = setdiff(obj.selectedRois, roiIndices);
                    
                    if any(obj.selectedRois == roiIndices)
                        if ~isempty(deselectedRois) 
                            if isMousePress
                                obj.unselectedRois = deselectedRois;
                            else
                                obj.deselectRois(deselectedRois)
                            end
                        else
                            obj.unselectedRois=[];
                        end
                    else
                        obj.deselectRois(deselectedRois)
                    end
                    
                    if isnan(roiIndices); roiIndices = []; end
                    if isempty(obj.selectedRois); obj.selectedRois=[]; end
                    
                case 'extend'

                    % Get roiIndices of roi that are newly selected and not
                    % already in the list of selected rois
                    if wasInRoi
                        roiIndices = setdiff(roiIndices, obj.selectedRois);
                    else
                        roiIndices = [];
                    end
                    
                otherwise
                    return
                    % Make sure to skip the last steps in this function if
                    % mode is right click.
                    
            end
            
            
            % Call the roiGroup's changeRoiSelection method to apply change
            if ~isempty(roiIndices)
                obj.roiGroup.changeRoiSelection(roiIndices, 'select')
            end
            
            
            %obj.updateCurrentRoiImage(obj.selectedRois(end));
            %obj.updateRoiInfoPanel()
            
% % %             if wasInRoi && numel(obj.selectedRois)==1
% % %                 obj.zoomOnRoi(obj.selectedRois(end))
% % %             end

        end
        
        function removeRois(obj)
           % Todo: Should this method be part of roimap?

           IND = obj.selectedRois;
           obj.deselectRois(IND)
           obj.roiGroup.removeRois(IND);

        end
        
        function deselectRois(obj, roiIndices)
        % Deselect all selected rois. Remove lines, reset color of roi in
        % image and unselect from listbox.
            
            if nargin < 2 || isempty(roiIndices)
                if ~isempty(obj.unselectedRois)
                    roiIndices = obj.unselectedRois;
                else
                    return; 
                end
            end
            
            obj.selectedRois = setdiff(obj.selectedRois, roiIndices);

            obj.roiGroup.changeRoiSelection(roiIndices, 'unselect')
        end
        
        function multiSelectRois(obj, xBounds, yBounds)
        %multiSelectRois Select rois in rectangular region
            xBounds = round(xBounds);
            yBounds = round(yBounds);

            currentFig = ancestor(obj.hAxes, 'figure');

            switch get(currentFig, 'SelectionType')
                case 'normal'
                    obj.deselectRois(obj.selectedRois)
            end
            
            markedRois = obj.getRoisInRegion(xBounds, yBounds);
            
            selectRois(obj, markedRois, 'extend');
            
        end
        
        function classifyRois(obj, classification)
            
            roiInd = obj.selectedRois;
            newClass = repmat(classification, size(roiInd));
            obj.roiGroup.setRoiClassification(...
                roiInd, newClass)
                        
        end
        
        function zoomInOnRoi(obj, i, forceZoom)
            
            if nargin < 3; forceZoom = false; end
            if nargin < 2 || isempty(i)
                i = obj.selectedRois(end);
            end

            % Zoom in on roi if roi is not within limits.
            xLim = obj.hAxes.XLim;
            yLim = obj.hAxes.YLim;

            roiCenter = obj.roiGroup.roiArray(i).center;
            
            % Decide if field of view should be changed (if roi is not inside image)
            [y,x] = find(obj.roiGroup.roiArray(i).mask);
            roiPositionLimits = [min(x), max(x); min(y), max(y)];
            if ~ ( roiPositionLimits(1,1) > xLim(1) && roiPositionLimits(1,2) < xLim(2) )
                changeFOV = true;
            elseif ~ ( roiPositionLimits(2,1) > yLim(1) && roiPositionLimits(2,2) < yLim(2) )
                changeFOV = true;
            else
                changeFOV = false;
            end
            
            
            if forceZoom % added later so works differently
                xLimNew = roiCenter(1) + [-75,75];
                yLimNew = roiCenter(2) + [-75,75];
                obj.displayApp.setNewImageLimits(xLimNew, yLimNew);
            end
            

            if changeFOV
                shiftX = roiCenter(1) - mean(xLim);
                shiftY = roiCenter(2) - mean(yLim);
                xLimNew = xLim + shiftX;
                yLimNew = yLim + shiftY;
                obj.displayApp.setNewImageLimits(xLimNew, yLimNew);
            end
            
        end
        
        function connectRois(obj)
            
            parentInd = obj.selectedRois(1);
            childInd = obj.selectedRois(2:end);
            
            obj.roiGroup.connectRois(parentInd, childInd)
            
        end
        
        % % % % Color settings
        
        function color = getRoiColor(obj, roi)
        % Return a color for the roi based on which group it belongs to.

            switch 'None' %'Validation Status' %obj.hRoimanager.settings.colorRoiBy
            %switch 'Classification' %'Validation Status'

                case 'Category'
                    groupmatch = cellfun(@(x) strcmp(x, roi.group), obj.roiClasses, 'uni', 0);
                    if any(cell2mat(groupmatch))
                        color = obj.roiColors{cell2mat(groupmatch)};
                    else
                        color = [0.3020    0.6863    0.2902];
                    end

% % %                 case 'Validation Status'
% % %                     % Check if roi was newly imported and still unresolved...
% % %                     if contains('imported', roi.tags)
% % %                         color = 'c';
% % %                     elseif contains('missing', roi.tags)
% % %                         color = 'r';
% % %                     elseif contains('improved', roi.tags)
% % %                         color = 'm';
% % %                     else
% % %                         color = ones(1,3)*0.8;
% % %                     end
                    
                case 'Validation Status' %'Classification'
                    clsf = getappdata(roi, 'roiClassification');
                    if isempty(clsf); color = ones(1,3)*0.8; return; end
                    
                    switch clsf
                        case 1
                            color = [0.174, 0.697, 0.492];
                        case 2
                            color = [0.920, 0.339, 0.378];
                        case 3
                            color = [0.176, 0.374, 0.908];
                        otherwise 
                            color =  ones(1,3)*0.9;
                            color = 'm';
                    end

                case 'Activity Level'
                    color = 'r';
                    
                case 'None'
                    color = obj.defaultColor;
                    
            end
        
        
        end

        function updateRoiColors(obj, roiInd)
            
            if nargin < 2; roiInd = 1:obj.roiGroup.roiCount; end
            
            for i = roiInd
                if ismember(i, obj.selectedRois); continue; end
                color = obj.getRoiColor(obj.roiGroup.roiArray(i));
                obj.roiPlotHandles(i).LineWidth = 0.5;
                obj.roiPlotHandles(i).Color = color;
                obj.roiTextHandles(i).Color = color;
            end
            
        end
        
    end

end