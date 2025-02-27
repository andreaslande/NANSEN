classdef selectObject < uim.interface.abstractPointer & ...
        uim.interface.pointerTool.mixin.DraggableRectangle
    
    properties (Constant)
        exitMode = 'default';
    end
    
    
    properties
        
        anchorPoint = [nan, nan]        	% defined in clib.hasDraggableRectangle
        previousPoint = [nan, nan] 

        isButtonDown = false
        
    end
    
    
    properties
        activeMode = ''       % Used for switching between different behaviors (selecting rois or moving rois) while mouse is pressed
        hObjectMap
        objectDisplacement = [0,0]
    end



    methods
               
        
        function obj = selectObject(hAxes, hObjectMap)
            obj.hAxes = hAxes;
            obj.hFigure = ancestor(hAxes, 'figure');
            
            if nargin >= 2  
                obj.hObjectMap = hObjectMap;
            end
            
        end
        
        
        function set.hObjectMap(obj, newValue)
            obj.hObjectMap = newValue;
        end
        

        function setPointerSymbol(obj)
            setptr(obj.hFigure, 'arrow');
        end
        
        
        function wasCaptured = onKeyPress(obj, src, event)
            wasCaptured = true;
            
            switch event.Key
                case {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0'}
                    if isempty(event.Modifier)
                        obj.hObjectMap.classifyRois(str2double(event.Key));
                    else
                        wasCaptured = false;
                    end
                    % Todo: change roi type using shift click??
                case 'a'
                    if contains('command', event.Modifier) || ...
                            contains('control', event.Modifier)
                        numRois = obj.hObjectMap.roiGroup.roiCount;
                        obj.hObjectMap.selectRois(1:numRois, 'extend')
                    else
                        wasCaptured = false;
                    end
                    
                case 'backspace'
                    obj.hObjectMap.removeRois;
                case 'g'
                    obj.hObjectMap.growRois();
                case 'h'
                    obj.hObjectMap.shrinkRois();
                case 'c'
                    if strcmp(event.Modifier, 'shift')
                        obj.hObjectMap.connectRois() % Todo: delegate to flufinder instead?
                    else
                        wasCaptured = false;
                    end
                case 'm'
                    if strcmp(event.Modifier, 'shift')
                        
                    else
                        wasCaptured = false;
                    end
                    % todo....
%                     if strcmp(event.Modifier, 'shift')
%                         obj.hObjectMap.mergeRois() % Todo: delegate to flufinder instead?
%                     end
                    
                %todo: arrowkeys for moving rois.

                otherwise
                    wasCaptured = false;
            end
        
        end
        
        
        function onButtonDown(obj, src, event)
        %onButtonDown Callback for handling button down events in a roiMap.  
                    
            obj.isButtonDown = true;
            obj.isActive = true;

            isRoiSelected = obj.hObjectMap.hittest(src, event);
            
            currentPoint = obj.hAxes.CurrentPoint(1, 1:2);
            obj.anchorPoint = currentPoint;
            obj.previousPoint = currentPoint;
            
            switch obj.hFigure.SelectionType
                
                case {'normal', 'extend'}
            
                    if isRoiSelected
                        obj.activeMode = 'moveObjects';
                    else
                        obj.activeMode = 'selectObjects';
                        obj.plotRectangle()
                    end
                    
                case 'open'
                    if isRoiSelected
                        obj.hObjectMap.zoomInOnRoi([], true)
                        obj.isActive = false;
                    end
            end

            
        end
        
        
        function onButtonMotion(obj, ~, ~)
            if isempty(obj.previousPoint); return; end
            if obj.isButtonDown && obj.isActive
                
                currentPoint = obj.hAxes.CurrentPoint(1, 1:2);

                switch obj.activeMode
                    case 'moveObjects'
                        
                        shift = currentPoint - obj.previousPoint;
                        obj.objectDisplacement = obj.objectDisplacement + shift;
                        obj.hObjectMap.shiftRoiPlot([shift, 0]);
                        
                    case 'selectObjects'
                    
                    	set(obj.hFigure, 'Pointer', 'crosshair');
                        obj.updateRectangle(currentPoint)
                end
                
                obj.previousPoint = currentPoint;
                
            end
        end
        
        
        function onButtonUp(obj, src, evt)
            if ~obj.isButtonDown; return; end % Button is released from a different component, i.e a toolbar button

            obj.isButtonDown = false;
            obj.isActive = false;
            
            axRange = mean( [diff(obj.hAxes.XLim), diff(obj.hAxes.YLim) ] );
            
            if all((abs(obj.anchorPoint - obj.previousPoint)) < axRange * 1e-3) % No movement
                obj.hObjectMap.deselectRois() % Unselect..
                
            else
                
                switch obj.activeMode 
                    case 'moveObjects'
                        
                        if any(obj.objectDisplacement ~= 0)
                            obj.hObjectMap.moveRoi(obj.objectDisplacement);
                            obj.objectDisplacement = [0, 0];
                        end
                
                    case 'selectObjects'
                
                        xBounds = sort( [obj.anchorPoint(1), obj.previousPoint(1)] );
                        yBounds = sort( [obj.anchorPoint(2), obj.previousPoint(2)] );

                        obj.resetRectangle();
                        obj.hObjectMap.multiSelectRois(xBounds, yBounds);
                end
            end
            
            % Reset active mode.
            obj.activeMode = '';
            
            obj.setPointerSymbol()
            obj.previousPoint = [nan, nan];
        end
        
    end

end