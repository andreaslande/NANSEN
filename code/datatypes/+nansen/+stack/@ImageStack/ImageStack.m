% Interface for reading and writing image frame data from a matlab array, 
% or tiff, binary or video files.
%
%   * Use for matlab array or virtual data (memorymap of data in file)
%   * Retrieve data using frame indices (channel / depth / time)
%   * Get frame chunks for batch processing of large data sets
%   * Get projections along depth or time dimensions
%
%   See also nansen.stack.ImageStack/ImageStack

classdef ImageStack < handle & uim.mixin.assignProperties
%ImageStack Wrapper for multi-dimensional image stack data
%
%   This class contains methods and properties for accessing image frames
%   in a standardized manner from a multidimensional data array. The data
%   can be a matlab array, or a VirtualData object.
%
%   A VirtualData object is a memory mapped representation of an image 
%   stack saved in a file, and some implementations include Binary, Tiff 
%   and video files. See VirtualData and existing subclasses for examples.
%
%   Data from an ImageStack is returned according to the default
%   dimensional order, YXCZT, corresponding to image height, image width,
%   channel/color, depth/planes (3D) and time respectively. If the length 
%   of any of these dimensions is 1 data is squeezed along that dimension.
%
%   The dimensional order of the output as well as the input can be
%   rearranged by providing a custom dimensional order using the letter
%   representations from above.
%
%   Furthermore, the apparent size of the ImageStack data can be
%   temporarily adjusted by setting the CurrentChannel and/or the 
%   CurrentPlane properties to a subset within the range of the 
%   NumChannels and NumPlanes properties
%
%   The ImageStack also provides methods for reading chunks of frames,
%   which can be useful for processing data from very large arrays that
%   don't fit in the computer memory.
%
%   Finally, the ImageStack class provides methods for calculating
%   projections along the depth or time dimensions.
%
%   EXAMPLES (Creating an ImageStack object):
%
%     imageStack = ImageStack(data) returns an ImageStack object based
%         on the data variable. The data variable must be an array with 2-5
%         dimensions.
%
%     imageStack = ImageStack(virtualData) returns an ImageStack object
%         based on the image data represented by the virtualData object.
%
%   DETAILED EXAMPLES (Use cases):    
%       


% - - - - - - - - QUESTIONS - - - - - - - - - - - 
%
%   1) Should output from getFrameSet be squeezed or not?
%
%   2) Should data not be deleted on destruction if it was provided as
%      input on construction.., i.e tied to imagestack or not??
%
%   3) How to set intensity limits without loading data on creation..




% - - - - - - - - - TODO - - - - - - - - - - - -
%   [ ] getFrameSet does not match description. Still not sure how to do
%       this in the best way. It should only grab according to last
%       dimension, and use CurrentPlane and CurrentChannel for selecting
%       subsets....
%   [ ] writeFrameSet same as above..
%
%   [ ] Add listener for DataCacheChanged and update flags for whether
%       projections should be updated...
%   [x] Permute output from getFrameSet to correspond with DimensionOrder
%       Actually, this is done in the imageStackData class...
%   [ ] Rename DimensionOrder and make it obvious what it refers to and how
%       its different from DataDimensionOrder.
%   [ ] Make method to return data size according to the
%       DefaultDimensionOrder 
%   [ ] More work on dimension selection for frame chunks.
%   [ ] Make ProjectionCache class and add as property...
%   [ ] Set method for name
%
%   [ ] Properties: FrameSize and NumFrames. Useful, Keep? 
%
%   [ ] Is chunklength implemented?
%
%   [ ] Method for loading userdata/metadata/projections...
%
%   [ ] Update insert image to work with imagestack data.
%

% - - - - - - - - - - - - PROPERTIES - - - - - - - - - - - - - - - - - - - 

    properties (Constant, Hidden) % Default values for dimension order
        DEFAULT_DIMENSION_ORDER = 'YXCZT'
        DIMENSION_LABELS = {'Height', 'Width', 'Channel', 'Plane', 'Time'}
    end
    
    properties % Properties containing ImageStack name and data
        Name char = 'UNNAMED'   % Name of ImageStack
        Data                    % Data ImageStackData
    end
    
    properties (Dependent)
        DimensionOrder          % Dimension arrangement of stack (i.e output) Depends on ImageStackData
    end
    
    properties (Dependent, Hidden)
        DataDimensionOrder      % Dimension arrangement of data (i.e source) Depends on ImageStackData
    end
    
    properties % Properties for customization of dimension lengths and units
        DimensionLength         % Length of each dimension, i.e 1 pixel = 1.5 micrometer
        DimensionUnits          % Units of each dimension, i.e [micrometer, micrometer, second] for XYT stack
    end
    
    properties 
        FileName char = ''      % Filename (absolute path for file) if data is a virtual array
        MetaData struct         % Metadata
        UserData struct         % Userdata 
        
        CurrentChannel = 1      % Sets the current channel(s). getFrames picks data from current channels
        CurrentPlane  = 1       % Sets the current plane(s). getFrames picks data from current planes
        
        ColorModel = ''         % Name of colormodel to use. Options: 'BW', 'Grayscale', 'RGB', 'Custom' | Should this be on the imviewer class instead?
        DataIntensityLimits
    end
    
    properties (SetAccess = private, Dependent) % Should these be dependent instead?
        ImageHeight
        ImageWidth
        NumChannels
        NumPlanes
        NumTimepoints
        DataType
    end
    
    properties (Hidden, Dependent)
        FrameSize % Todo: Is this used?
        NumFrames % Todo: Is this used? Is it the product of channels, planes and timepoints?
        
        DimensionNames          % Names for dimensions of image stack data, i.e ImageHeight, Channels etc
        DynamicCacheEnabled matlab.lang.OnOffSwitchState % Depends on ImageStackData
        DataTypeIntensityLimits     % Min and max values of datatype i.e [0,255] for uin8 data
    end
    
    properties (Access = private) % Should it be public? 
        Projections
    end
    
    properties (SetAccess = private) % Dependent (For virtual data)
        IsVirtual
        HasStaticCache = false
    end
    
    properties (Hidden)
        CustomColorModel = []
        ChunkLength = inf; % Todo (Not implemented yet)
    end

    properties (Dependent = true)
        NumChunks
    end

    properties (Access = private)
        CacheChangedListener
        isDirty struct % Temp flag for whether buffer was updated... Should be moved to virtualStack...
    end
    

% - - - - - - - - - - - - - METHODS - - - - - - - - - - - - - - - - - - - 

    methods % Structors
        
        function obj = ImageStack(datareference, varargin)
        %ImageStack Constructor of ImageStack objects
        %
        %   imageStack = ImageStack(data) returns an ImageStack object 
        %       based on the data variable. The data variable must be an 
        %       array with 2-5 dimensions.
        %
        %   imageStack = ImageStack(virtualData) returns an ImageStack 
        %       object based on the image data represented by the 
        %       virtualData object.   
        %
        %   imageStack = ImageStack(..., Name, Value) creates the
        %       ImageStack object and specifies values of properties on
        %       construction.
        %
        %   PARAMETERS (See property descriptions for details): 
        %       Name, CurrentChannel, CurrentPlane, ColorModel, 
        %       DataDimensionOrder, CustomColorModel, DynamicCacheEnabled,
        %       ChunkLength
        %
        
            if ~nargin; return; end
            
            % This method creates the appropriate subclass of 
            % ImageStackData and the returned object is assigned to the
            % Data property. See also onDataSet
            obj.Data = obj.initializeData(datareference, varargin{:});
            
            obj.parseInputs(varargin{:})
            
            % Todo: method for loading userdata/metadata/projections...
            
            % Todo: Part of onDataSet?
%             if isempty( obj.DataIntensityLimits )
%                 obj.autoAssignDataIntensityLimits()
%             end
            
            if isempty(obj.ColorModel)
                obj.autoAssignColorModel()
            end
            
        end
        
        function delete(obj)
            
            if obj.IsVirtual
                delete(obj.CacheChangedListener)
            end
            
            % Delete the data property.
            % Todo: Only delete if data is created internally. 
            if ~isempty(obj.Data) && isvalid(obj.Data)
                delete(obj.Data)
            end
            
        end

    end

    methods % User methods
        
    % - Methods for accessing data using frame indices
        
        function imArray = getFrameSet(obj, frameInd)
        %getFrameSet Get set of image frames from image stack
        %
        %   imArray = imageStack.getFrameSet(indN) gets the frames
        %   specified by the vector, indN, where indN specified the frame
        %   indices along the last dimension of the ImageStack Data. 
        %   
        %   imArray = imageStack.getFrameSet(indN, indN-1) gets frames as
        %   subset where indN and indN-1 are indices to get along the last
        %   two dimensions of the Data.
        %
        %   imArray = imageStack.getFrameSet('all') returns all available
        %   frames. For VirtualData, all available frames equals frames in
        %   the Cache. If Caching is off, a subset of N frmaes are
        %   retrieved.
        %
        %   NOTE: The behavior of getFrameSet is influenced by the values
        %   of CurrentChannel and CurrentPlane. I.e: If CurrentChannel is
        %   set to 1, and the data contains 3 channels, only data from the
        %   first channel is retrieved, even if more channelIndices are
        %   specifiec in inputs. To override this behavior, index the Data 
        %   property instead.
        %
        %   Note: If the length of any of the frame dimensions (channel /
        %   plane / time) is one, this dimension is not regarded.
        %
        %   Examples:
        %     1) imageStack is XYCT.
        %       data = imageStack.getFrameSet(1:10) will return an array of
        %       size h x w x numChannels x 10
        %
        %       data = imageStack.getFrameSet(1:10, 1:2) will return an 
        %       array of size h x w x 2 x 10
        %
        %       However: If CurrentChannel is set to 1, the data will be of
        %       size h x w x 10
        %
        %     2) imageStack is XYCZT.
        %       data = imageStack.getFrameSet(1:10) will return an array of
        %       size h x w x numChannels x numPlanes x 10
        %
        %       data = imageStack.getFrameSet(1:10, 1:3) will return an 
        %       array of size h x w x numChannels x 3 x 10
        %
        %     3) imageStack is XYZCT.
        %       data = imageStack.getFrameSet(1:10, 1:3) will return an 
        %       array of size h x w x numPlanes x 3 x 10
        
            indexingSubs = obj.getDataIndexingStructure(frameInd);
                  
            % Case 1: All frames (along last dimension) are requested.
            if ischar(frameInd) && strcmp(frameInd, 'all')
                
                % Todo: Should return cached frames if number of frames
                % will not fit in memory??
                
                % Assign image data to temp variable.
                if obj.IsVirtual
                    try
                        imArray = obj.Data.getCachedFrames();
                    catch
                        imArray = obj.Data(indexingSubs{:});
                    end

                else
                    imArray = obj.Data.DataArray;
                end
                
            % Case 2: Subset of frames are requested.
            else
                imArray = obj.Data(indexingSubs{:});
            end
            
            % Set data intensity limits based on current data if needed.
            if isempty( obj.DataIntensityLimits )
                obj.autoAssignDataIntensityLimits(imArray) % todo
            end


        end
        
        function writeFrameSet(obj, imageArray, frameInd)
        %writeFrameSet Write set of image frames to image stack
            
            % Get indexing subs for assigning to Data
            %[indC, indZ, indT] = obj.getFrameInd(varargin{:});
            indexingSubs = obj.getDataIndexingStructure(frameInd);
    
            % Make sure dimensions match with imageArray.
            isColon = @(x) ischar(x) && strcmp(x, ':');
            isDimensionSubset = ~cellfun(@(x)isColon(x), indexingSubs);
            dimensionLength = cellfun(@numel, indexingSubs(isDimensionSubset));
           
            % Assign imArray to indexes of Data
            assert(isequal(dimensionLength, size(imageArray, find(isDimensionSubset)) ), ...
                'Frame indices and data size does not match')
            obj.Data(indexingSubs{:}) = imageArray;
           
        end
        
        function imArray = getCompleteFrameSet(obj, frameInd)
            % Returns a frameset disregarding current channel and current
            % plane settings
            
            indexingSubs = obj.getFullDataIndexingStructure();
            if ~ischar(frameInd) && ~strcmp(frameInd, 'all')
                indexingSubs{end} = frameInd;
            end
            
            imArray = obj.Data(indexingSubs{:});

        end
        
        function addToStaticCache(obj, imData, frameIndices)
            
            if ~obj.IsVirtual
                error('Data can only be added to static cache for ImageStack with virtual data')
            end
            
            obj.Data.addToStaticCache(imData, frameIndices)
            
        end
        
        function insertImage(obj, newImage, insertInd, dim)
            
            error('Down for maintentance...')
            
            if obj.IsVirtual
                error('Can not insert image into virtual data stack')
            end
            
            if nargin < 4 || isempty(dim)
                dim = 'T';
            end
            
            if all( size(newImage, 1,2) < obj.Size(1,2) )
                newImage = stack.reshape.imexpand(newImage, obj.Size(1,2));
            elseif all( size(newImage, 1,2) < obj.Size(1,2) )
                newImage = stack.reshape.imcropcenter(newImage, obj.Size(1,2));
            end
            
            % Todo: Make sure image which is inserted has same number of
            % channels and planes as Data
            
            isSizeEqual = isequal( size(newImage, 1, 2), obj.Size(1,2));
            assert(isSizeEqual, 'Image Dimensions do not match')
            
            dim = strfind(obj.DataDimensionOrder, dim);
            
            subs = obj.getFullDataIndexingStructure();
            %subs{dim} = insertInd;
            
            % Todo: Adapt according to dimensions....
            if insertInd == 1
                obj.Data = cat(dim, newImage, ...
                    obj.Data(subs{:}));
            else
                % Todo: Use insert into array function... Todo:
                [subsPre, subsPost] = deal(subs);
                subsPre{dim} = 1:insertInd(1)-1;
                subsPost{dim} = insertInd(1):subsPost{dim}(end);

                obj.Data = cat(dim, obj.Data(subsPre{:}), ...
                    newImage, obj.Data(subsPost{:}) );
            end

            % Todo: are all "dependent" properties updated?
            
            % Todo: 
            % Make sure classes are compatible
            % Make sure it works for 4dimensional arrays as well.
            % MAke implementation for inserting stacks.
        end
        
        function removeImage(obj, location, dim)
                    
            if obj.IsVirtual
                error('Can not remove image from virtual data stack')
            end
            
            error('Not implemented')
            
        end
        
    % - Methods for getting processed versions of data
    
        function downsampledStack = downsampleT(obj, n, method, varargin)
        %downsampleT Downsample stack by a given factor
        %
        %   downsampledStack = obj.downsampleT(n) where n is the
        %   downsampling factor.
        %
        %   downsampledStack = obj.downsampleT(n, method) performs the
        %   downsampling using the specified method. Default is 'mean', i.e
        %   the stack is binned by n frames at a time, and the result is
        %   the mean of each bin.
        %    
        %   downsampledStack = obj.downsampleT(n, method, name, value, ...)
        %   performs the downsampling according to specified name-value
        %   parameters.
        %
        %   Downsample stack through binning frames and calculating a
        %   projection for frames within each bin. n is the binsize and
        %   method specifies what projection to compute. Method can be 
        %   'mean', 'max', 'min'
        %
        %   Output can be a virtual or a direct imageStack. Output data
        %   type will be the same as input, but can be specified...
       
        
            % TODO: validate that imagestack contains a T dimension..
            % TODO: only works for 3d stacks..
            
            if nargin < 3 || isempty(method)
                method = 'mean';
            end
        
            params = struct();
            params.CreateVirtualOutput = false;
            params.UseTransientVirtualStack = true;
            params.FilePath = '';
            params.OutputDataType = 'same';
            
            params = utility.parsenvpairs(params, 1, varargin{:});
            %nvPairs = utility.struct2nvpairs(params);
            
            % Calculate number of downsampled frames
            numFramesFinal = floor( obj.NumTimepoints / n );
            
            % Get (or set) block size for downsampling. 
            % Todo: get automatically based on memory function
            if obj.ChunkLength == inf
                chunkLength = 2000;
            else
                chunkLength = obj.ChunkLength;
            end
            
            % Determine if we need to save data to file
            if obj.IsVirtual && numFramesFinal > chunkLength 
                params.CreateVirtualOutput = true;
            end
            
            % Create a new ImageStack object, which is an instance of a
            % downSampled stack.
            downsampledStack = nansen.stack.DownsampledStack(obj, n, method, params);
            
            % Get indices for different parts/blocks
            [IND, numChunks] = obj.getChunkedFrameIndices(chunkLength);
            
            % Todo: Should this be commented out or not??
            
            % Loop through blocks and downsample frames
            for iPart = 1:numChunks
                imData = obj.getFrameSet( IND{iPart} );
                downsampledStack.addFrames(imData); 
            end
            
        end
        
        function projectionImage = getFullProjection(obj, projectionName)
        %getFullProjection Get stack projection image from the full stack
        
            % No need to calculate again if projection already exists
            if (isfield(obj.Projections, projectionName) && ~obj.IsVirtual) || ...
                (isfield(obj.Projections, projectionName) && obj.IsVirtual && ~obj.isDirty.(projectionName))
            
                projectionImage = obj.Projections.(projectionName);
                return 
            end
            
            global fprintf % Use highjacked fprintf if available
            if isempty(fprintf); fprintf = str2func('fprintf'); end
                       
            fprintf(sprintf('Calculating %s projection...\n', projectionName))

            projectionImage = obj.getProjection(projectionName, 'all');
            
            % Assign projection image to stackProjection property
            obj.Projections.(projectionName) = projectionImage;
            if isempty(obj.isDirty)
                obj.isDirty = struct(projectionName, false);
            else
                obj.isDirty.(projectionName) = false;
            end
        end
        
        function projectionImage = getProjection(obj, projectionName, frameInd, dim)
        % getProjection Get stack projection image
        %
        %   Projection is always calculated along the last dimension unless
        %   something else is specified.
            
            % Todo: Put a limit on how many images to use for getting
            % percentiles of pixel values.
        
            if nargin < 3 || isempty(frameInd); frameInd = 'all'; end
            
            tmpStack = obj.getFrameSet(frameInd);

            % Todo: Handle different datatypes..
            %       i.e cast output to original type. Some functions
            %       require input to be single or double...
            
            
            % Set dimension to calculate projection image over.
            
            if nargin < 4 || isempty(dim)
                dim = ndims(tmpStack);
            else
                error('Not implemented yet')
            end
            
            % Calculate the projection image
            switch lower(projectionName)
                case {'avg', 'mean', 'average'}
                    projectionImage = mean(tmpStack, dim);
                    projectionImage = cast(projectionImage, obj.DataType);
                    
                case {'std', 'standard_deviation'}
                    P = double( prctile(single(tmpStack(:)), [0.5, 99.5]) );
                    projectionImage = std(single(tmpStack), 0, dim);
                    projectionImage = (projectionImage - (min(projectionImage(:)))) ./ ...
                        range(projectionImage(:));
                    
                    projectionImage = projectionImage .* range(P) + P(1);
                    projectionImage = cast(projectionImage, class(tmpStack));
                    %projectionImage = stack.makeuint8(projectionImage);
                case {'max', 'maximum'}
                    projectionImage = max(tmpStack, [], dim);
                    
                case 'correlation'
                    % todo
                case 'clahe'
                    % todo
                    
                otherwise
                    
                    projFun = nansen.stack.utility.getProjectionFunction(projectionName);
                    projectionImage = projFun(tmpStack, dim);

            end
            
        end
        
        function calculateProjection(obj, funcHandle)
            
        end
        
    % - Methods for getting frame chunks 
            
        function frameInd = getMovingWindowFrameIndices(obj, frameNum, windowLength, dim)
        %getMovingWindowFrameIndices Get frame indices for binned set of frames
        %
        %   frameInd = getBinningFrames(obj, frameNum, binningSize) returns
        %   frame indices frameInd around the frame given by frameNum. The
        %   length of frameInd is determined by binningSize.
        %
        %   % If the binned frames exceeds the image stack in the beginning
        %   or the end, the number of frame indices will be cut off. Also,
        %   if the number of images in the stack are fewer than the
        %   requested bin size, the frame indices are "cut off".
        
            if nargin < 4 || isempty(dim)
                dim = 'T';
            end
        
            assert(any(strcmp(dim, {'C', 'Z', 'T'})), 'dim must be ''C'', ''Z'', or ''T''')
            numFrames = obj.getDimensionLength(dim);

            if frameNum <= ceil( windowLength/2 )
                frameInd = 1:min([numFrames, windowLength]);
                
            elseif (numFrames - frameNum) < ceil( windowLength/2 )
                frameInd = max([numFrames-windowLength+1,1]):numFrames;
            
            else
                halfWidth = floor( windowLength/2 );
                frameInd = frameNum + (-halfWidth:halfWidth);
            end
            
        end
        
        function N = chooseChunkLength(obj, dataType, pctMemoryLoad, dim)
        %chooseChunkLength Find good number of frames for batch-processing
        %
        %   N = imageStack.chooseChunkLength() returns the number of frames (N) 
        %   for an ImageStack object that would use 1/8 of the available
        %   system memory.
        %
        %   N = hImageStack.chooseChunkLength(dataType) returns the number of
        %   frames that will use 1/8 of the system memory for imagedata 
        %   which is recast to another type. dataType can be any of the 
        %   numeric classes of matlab (uint8, int8, uint16, etc, single, 
        %   double).
        %
        %   N = hImageStack.chooseChunkLength(dataType, pctMemoryLoad) 
        %   adjusts number of frames to only use a given percentage of the
        %   available memory.
        %
        %   N = hImageStack.chooseChunkLength(dataType, pctMemoryLoad, dim)
        %   find chunk length along a different dimension that default
        %   (Default = T)
        
            if nargin < 2 || isempty(dataType)
                dataType = obj.DataType;
            end
            
            if nargin < 3 || isempty(pctMemoryLoad)
                pctMemoryLoad = 1/8;
            end
            
            if nargin < 4 || isempty(dim)
                dim = 'T';
            end
            
            availMemoryBytes = system.getAvailableMemory();

            % Adjust available memory according to the memory load
            availMemoryBytes = availMemoryBytes * pctMemoryLoad;

            numBytesPerFrame = obj.getImageDataByteSize(obj.FrameSize, dataType);
            
            N = floor( availMemoryBytes / numBytesPerFrame );

            % Adjust based on selected dimension.
            switch dim
                case 'T'
                    N = N / obj.NumChannels / obj.NumPlanes;
                case 'Z'
                    N = N / obj.NumChannels / obj.NumTimepoints;
                case 'C'
                    N = N / obj.NumPlanes / obj.NumTimepoints;
            end
            
        end
        
        function [IND, numChunks] = getChunkedFrameIndices(obj, numFramesPerChunk, chunkInd, dim)
        %getChunkedFrameIndices Calculate frame indices for each subpart
            
            if nargin < 2 || isempty(numFramesPerChunk)
                numFramesPerChunk = obj.ChunkLength;
            end
            
            if nargin < 3 || isempty(chunkInd)
                chunkInd = [];
            end
            
            if nargin < 4 || isempty(dim)
                dim = 'T';
            end
            
            assert(any(strcmp(dim, {'C', 'Z', 'T'})), 'dim must be ''C'', ''Z'', or ''T''')
            
            numFramesDim = obj.getDimensionLength(dim);

            % Make sure chunk length does not exceed number of frames.
            numFramesPerChunk = min([numFramesPerChunk, numFramesDim]);

            % Determine first and last frame index for each chunk
            firstFrames = 1:numFramesPerChunk:numFramesDim;
            lastFrames = firstFrames + numFramesPerChunk - 1;
            lastFrames(end) = numFramesDim;
            
            % Create cell array of frame indices for each block/part.
            numChunks = numel(firstFrames);
            IND = arrayfun(@(i) firstFrames(i):lastFrames(i), 1:numChunks, 'uni', 0);
           
            if ~isempty(chunkInd)
                if numel(chunkInd) == 1
                    IND = IND{chunkInd}; % Return as array
                else
                    IND = IND(chunkInd); % Return as cell array
                end
                
            end
            
            if nargout == 1
                clear numChunks
            end
        end
        
        function [imArray, IND] = getFrameChunk(obj, chunkNumber)
            
            IND = obj.getChunkedFrameIndices([], chunkNumber);
            imArray = obj.getFrameSet(IND);

            % Todo: This only works as intended if T is the last
            % dimension..
            
            if nargout == 1
                clear IND
            end
            
        end
        
    % - Methods for getting data specific information
        
        function length = getDimensionLength(obj, dimName)
        %getDimensionLength Get length of dimension given dimension label
        %
        %   TODO: Combine with private method getStackDimensionLength
        
            switch dimName
                case {'T', 'Time'}
                    length = obj.NumTimepoints;
                case {'C', 'Channel'}
                    length = obj.NumChannels;
                case {'Z', 'Plane'}
                    length = obj.Planes;
                case {'X', 'Width', 'ImageWidth'}
                    length = obj.ImageWidth;
                case {'Y', 'Height', 'ImageHeight'}
                    length = obj.ImageHeight;
            end
            
        end

    end
    
    methods % Set/get methods
        
        function set.Data(obj, newValue)
            obj.Data = newValue;
            obj.onDataSet()
        end
        
        function set.CurrentChannel(obj, newValue)
            msg = 'CurrentChannel must be a vector where all elements are in the range of number of channels';
            assert(all(ismember(newValue, 1:obj.NumChannels)), msg) %#ok<MCSUP> This should not be a problem because...
            
            obj.CurrentChannel = newValue;
        end
        
        function set.CurrentPlane(obj, newValue)
            msg = sprintf('CurrentPlane must be a vector where all elements are in the range of [1, %d]', obj.NumPlanes); %#ok<MCSUP>
            assert(all(ismember(newValue, 1:obj.NumPlanes)), msg) %#ok<MCSUP> This should not be a problem because...
            
            obj.CurrentPlane = newValue;
        end
      
        function set.ColorModel(obj, newValue)
            %= 'RGB' % Mono, rgb, custom
            msg = 'ColorModel must be ''BW'', ''Grayscale'', ''RGB'' or ''Custom''';
            assert(any(strcmp({'BW', 'Grayscale', 'RGB', 'Custom'}, newValue)), msg)
            obj.ColorModel = newValue; 
        end
        
        function set.DimensionOrder(obj, newValue)
            if isempty(obj.Data); return;end
            obj.Data.StackDimensionArrangement = newValue;
            obj.onDataDimensionOrderChanged()
        end
        
        function value = get.DimensionOrder(obj)
            if isempty(obj.Data); return;end
            value = sprintf('%s (%s)', obj.Data.StackDimensionArrangement, ...
                obj.DimensionNames);
        end
        
        function set.DataDimensionOrder(obj, newValue)
            if isempty(obj.Data); return;end
            obj.Data.DataDimensionArrangement = newValue;
            obj.onDataDimensionOrderChanged()
        end
        
        function value = get.DataDimensionOrder(obj)
            if isempty(obj.Data); return;end
            value = sprintf('%s (%s)', obj.Data.DataDimensionArrangement, ...
                obj.DimensionNames);
        end
        
        function names = get.DimensionNames(obj)
            [~, ~, iB] = intersect(obj.Data.StackDimensionArrangement, ...
                obj.DEFAULT_DIMENSION_ORDER, 'stable');
            
            names = strjoin(obj.DIMENSION_LABELS(iB), ' x ');
            
        end
        
        function dimLength = get.ImageHeight(obj)
            dimLength = obj.getStackDimensionLength('Y');
        end
        
        function dimLength = get.ImageWidth(obj)
            dimLength = obj.getStackDimensionLength('X');
        end
        
        function dimLength = get.NumChannels(obj)
            dimLength = obj.getStackDimensionLength('C');
        end
        
        function dimLength = get.NumPlanes(obj)
            dimLength = obj.getStackDimensionLength('Z');
        end
        
        function dimLength = get.NumTimepoints(obj)
            dimLength = obj.getStackDimensionLength('T');
        end
        
        function dataType = get.DataType(obj)
            dataType = obj.Data.DataType;
        end
        
        function set.ChunkLength(obj, newValue)
            
            classes = {'numeric'};
            attributes = {'integer', 'nonnegative'};
            validateattributes(newValue, classes, attributes)
                
            if obj.ChunkLength == inf || obj.ChunkLength == newValue
                obj.ChunkLength = newValue;
            else
                warning('ChunkLength is already set and can not be set again')
            end
            
        end
        
        function set.DynamicCacheEnabled(obj, newValue)
            obj.Data.UseDynamicCache = newValue;
        end
        
        function state = get.DynamicCacheEnabled(obj)
            state = obj.Data.UseDynamicCache;
        end

        function tf = get.HasStaticCache(obj)
            
            tf = false;
            
            if obj.IsVirtual
                tf = obj.Data.HasStaticCache;
            end

        end
        
        function numChunks = get.NumChunks(obj)
            % Todo: Depend on chunking dimension..
            numChunks = ceil( obj.numTimepoints / obj.ChunkLength );
        end
        
        function numFrames = get.NumFrames(obj)
            numFrames = obj.NumChannels * obj.NumPlanes * obj.NumTimepoints;
        end
        
        function frameSize = get.FrameSize(obj)
         frameSize = [obj.ImageHeight, obj.ImageWidth];
        end
        
        function clim = get.DataTypeIntensityLimits(obj)
            clim = obj.getDataTypeIntensityLimits(obj.DataType);
        end
        
    end

    methods (Access = private) % Internal methods
       
    % - Methods for getting the indices according to the dimension order
        
        function [indC, indZ, indT] = getFrameInd(obj, varargin)
        %getFrameInd Get frame indices for the each dimension (C, Z, T)
        
            % Todo: input validation...
        
            if ischar(varargin{1}) && strcmp(varargin{1}, 'all')
                
                indC = obj.CurrentChannel;
                indZ = obj.CurrentPlane;
                indT = 1:obj.NumTimepoints;

            else
                
                % Initialize:
                [indC, indZ, indT] = deal(1);
            
                for i = 1:numel(varargin)
                    
                    thisDim = obj.DataDimensionOrder(end-i+1); % Start from end
                    
                    switch thisDim
                        case 'T'
                            indT = varargin{i};
                        case 'C'
                            indC = varargin{i};
                        case 'Z'
                            indZ = varargin{i};
                    end
            
                end
                
                % Todo: Add checks to ensure indices stays within valid
                % range
                
            end
            
        end
        
        function subs = getDataIndexingStructure(obj, frameInd)
        %getDataIndexingStructure Get cell of subs for indexing data
        %
        %   Returns a cell array of subs for retrieving data given a list
        %   of frameInd. frameInd is a list of frames to retrieve, where
        %   the frames are taken from the last dimension of data (assuming
        %   the last dimension is time (T) or depth (Z). 
        %
        %   Subs for the image X- and Y- dimensions are set to ':' while 
        %   subs for channels are set based on the CurrentChannel property.
        %   If the stack is 5D, containing both time and depth, the planes
        %   will be selected according to the CurrentPlane property.
        % 
        %   Note, if frameInd is equal to 'all', the subs of the last
        %   dimension will be equivalent to ':'
            
            numDims = ndims(obj.Data);
                        
            % Initialize list of subs
            subs = cell(1, numDims);
            subs(:) = {':'};
            
            for i = 1:numDims
                
                thisDim = obj.DataDimensionOrder(i);
                
                switch thisDim
                    case 'C'
                        subs{i} = obj.CurrentChannel;
                        
                    case 'Z'
                        
                        if i == numDims
                            if ischar(frameInd) && strcmp(frameInd, 'all')
                                subs{i} = 1:obj.NumPlanes;
                            else
                                subs{i} = frameInd;
                            end
                        else
                            subs{i} = obj.CurrentPlane;
                        end
                        
                    case 'T'
                        if i == numDims
                            if ischar(frameInd) && strcmp(frameInd, 'all')
                                subs{i} = 1:obj.NumTimepoints;
                            else
                                subs{i} = frameInd;
                            end
                        else
                            subs{i} = 1:obj.NumTimepoints;
                        end

                    case {'X', 'Y'}
                        %pass
                end
            end
            
        end

        function subs = getFullDataIndexingStructure(obj)
            
            numDims = numel(obj.DataDimensionOrder);
            
            % Initialize list of subs
            subs = cell(1, numDims);
            for i = 1:numDims
                thisDim = obj.DataDimensionOrder(i);
                subs{i} = 1:obj.getDimensionLength(thisDim); 
            end
            
        end
        
        
    % - Methods for assigning property values based on data
        
        function autoAssignDataIntensityLimits(obj, tmpData)
            %autoAssignDataIntensityLimits Set brightness limits of stack
        
            % Get a subset of of the image data
            if nargin < 2 || isempty(tmpData)
                tmpData = obj.getFrameSet(1:min([31, obj.NumTimepoints]));
            end
            
            [S, L] = bounds(tmpData(:));

            if isnan(S); S = 0; end
            if isnan(L); L = 1; end
            
            obj.DataIntensityLimits = double( [S, L] );
        end
        
        function autoAssignColorModel(obj)
        
            if obj.NumChannels == 1
            	obj.ColorModel = 'Grayscale';
            elseif obj.NumChannels == 3
            	obj.ColorModel = 'RGB';
            else
                obj.ColorModel = 'Custom';
                if isempty(obj.CustomColorModel)
                    obj.CustomColorModel = hsv(obj.NumChannels);
                end
            end
            
            % Todo: Set CustomColorModel, i.e color for each channel
            
            
            if islogical(obj.Data)
                obj.ColorModel = 'BW';
            end
            
            % Todo: what if there are multichannel logical arrays?
            
        end
        
        function onCachedDataChanged(obj, src, evt)
            %error('not implemented')
        end
        
    % - Methods for getting dimension lengths
        
        function dimNum = getDimensionNumber(obj, dimName)
            dimNum = strfind(obj.Data.StackDimensionArrangement, dimName);
        end
        
        function dimLength = getStackDimensionLength(obj, dimLabel)
            
            ind = strfind(obj.Data.StackDimensionArrangement, dimLabel);
                
            if isempty(ind)
                dimLength = 1;
            else
                dimLength = size(obj.Data, ind);
            end

        end
        
    end
    
    methods (Access = private) % Callbacks for property value set
        
        function onDataSet(obj)
            
            % Set some property values that depends on whether data is
            % virtual or not.
            if isa(obj.Data, 'nansen.stack.data.VirtualArray')
                obj.IsVirtual = true;

                obj.CacheChangedListener = listener(obj.Data, ...
                    'DynamicCacheChanged', @obj.onCachedDataChanged);
                
                obj.FileName = obj.Data.FilePath;
                [~, obj.Name] = fileparts(obj.Data.FilePath);
                
            else
                
                obj.IsVirtual = false;

                if ~isempty(obj.CacheChangedListener)
                    delete(obj.CacheChangedListener)
                    obj.CacheChangedListener = [];
                end

            end
            
            if ~obj.IsVirtual
                obj.autoAssignDataIntensityLimits()
            end
            
            % Set size
            obj.onDataDimensionOrderChanged()

            obj.CurrentChannel = 1:obj.NumChannels;
            
        end
        
        function onDataDimensionOrderChanged(obj)
            
            % This is outsource to ImageStackData..
            % IS there any reason to keep this method??
            
% %             stackSize = size(obj.Data);
% %             
% %             % Assign property value for each of the dimension lengths
% %             for i = 1:numel(obj.DEFAULT_DIMENSION_ORDER)
% %                 
% %                 thisDim = obj.DEFAULT_DIMENSION_ORDER(i);
% %                 ind = strfind(obj.Data.StackDimensionArrangement, thisDim);
% %                 
% %                 if isempty(ind)
% %                     dimLength = 1;
% %                 else
% %                     dimLength = stackSize(ind);
% %                 end
% %                 
% %                 switch thisDim
% %                     
% %                     case 'Y'
% %                         obj.ImageHeight = dimLength;
% %                     case 'X'
% %                         obj.ImageWidth = dimLength;
% %                     case 'C'
% %                         obj.NumChannels = dimLength;
% %                     case 'Z'
% %                         obj.NumPlanes = dimLength;
% %                     case 'T'
% %                         obj.NumTimepoints = dimLength;
% %                 end
% %                 
% %             end
        end
        
    end
    
    methods (Static)
        
        function imageStack = validate(imageData)
        %validate Validate image stack
        %
        % This function checks if a variable/object is an image array or an
        % ImageStack object. If the variable is numeric and has 3 or more
        % dimension, it is returned as an ImageStack.
            
            % If image data is numeric, place it in an ImageStack object.
            if isa(imageData, 'numeric')
                message = 'Image data must have at least 3 dimensions';
                assert( ndims(imageData) >= 3, message ) %#ok<ISMAT>
                imageStack = nansen.stack.ImageStack(imageData);
                
            elseif isa(imageData, 'nansen.stack.data.abstract.ImageStackData')
                imageStack = nansen.stack.ImageStack(imageData);
                
            elseif isa(imageData, 'imviewer.ImageStack')
                imageStack = imageData;
                
            else
                message = 'Image data must be a numeric array or an ImageStack object';
                error(message)
            end
            
        end
        
        function byteSize = getImageDataByteSize(imageSize, dataType)
            
            switch dataType
                case {'uint8', 'int8', 'logical'}
                    bytesPerPixel = 1;
                case {'uint16', 'int16'}
                    bytesPerPixel = 2;
                case {'uint32', 'int32', 'single'}
                    bytesPerPixel = 4;
                case {'uint64', 'int64', 'double'}
                    bytesPerPixel = 8;
            end
            
            byteSize = prod(imageSize) .* bytesPerPixel;
            
        end
        
        function limits = getDataTypeIntensityLimits(dataType)
            
            switch dataType
                case 'uint8'
                    limits = [0, 2^8-1];
                case 'uint16'
                    limits = [0, 2^16-1];
                case 'uint32'
                    limits = [0, 2^32-1];
                case 'int8'
                    limits = [-2^7, 2^7-1];
                case 'int16'
                    limits = [-2^15, 2^15-1];
                case 'int32'
                    limits = [-2^31, 2^31-1];
                case {'single', 'double'}
                    limits = [0, 1];
            end
            
        end
        
    end
    
    methods (Static) %Methods in separate files
        data = initializeData(datareference, varargin)
        
    end
    
end