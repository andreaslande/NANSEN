
% Class for indexing data from a binary file in the same manner that data 
% is indexed from matlab arrays.

classdef Binary < nansen.stack.data.VirtualArray

    
    % Todo: 
    %   [ ] Generalize.
    %   [x] Rename to binary
    %   [ ] Open input dialog to enter info about how to open data (format)
    %       if ini file is not available
    %   [ ] Implement data write functionality.
    %   [ ] Add methods for writing ini variables...
    
    %   [x] Add list of file formats, i.e .raw and .bin??
    
properties (Constant)
    FILE_FORMATS = {'RAW', 'BIN'} 
end
    
properties (Access = private, Hidden)
    MemMap
end


methods % Structors
    
    function obj = Binary(filePath, varargin)
       
        % Open folder browser if there are no inputs.
        if nargin < 1; filePath = uigetdir; end
        
        if isa(filePath, 'char')
            filePath = {filePath};
        end
        
        % Create a virtual stack object
        obj@nansen.stack.data.VirtualArray(filePath, varargin{:})
        
    end
       
end

methods (Access = protected) % Implementation of abstract methods
        
    function assignFilePath(obj, filePath, ~)
    %ASSIGNFILEPATH Assign path to the raw imaging data file.
    %
    %   Resolve whether the input pathString is pointing to the recording
    %   .ini file, the recording .raw file or the recording folder.
    
    %   Todo: implement different types of file formats according to the
    %   FILE FORMATS property.
    
        if isa(filePath, 'cell') && numel(filePath)==1
            filePath = filePath{1};
        end
        
        % Find fileName from folderPath
        if contains(filePath, '.raw')
            [folderPath, fileName, ext] = fileparts(filePath);
            fileName = strcat(fileName, ext);
            
        elseif contains(filePath, '.ini')
            [folderPath, fileName, ~] = fileparts(filePath);
            fileName = strcat(fileName, '.raw');
            
        elseif isfolder(filePath)
            folderPath = filePath;
            listing = dir(fullfile(folderPath, '*.raw'));
            fileName = listing(1).name;
            if isempty(fileName) 
                error('Did not find raw file in the specified folder')
            end
            
        else
            error('Something went wrong. Filepath does not point to a Binary Image file.')
        end
        
        obj.FilePath = fullfile(folderPath, fileName);
        
    end
    
    function getFileInfo(obj)
        
        obj.MetaData = obj.readinifile();

        obj.assignDataSize()
        
        obj.assignDataType()
        
    end
    
    function createMemoryMap(obj)
        
        mapFormat = {obj.DataType, obj.DataSize, 'ImageArray'};
        
        % Memory map the file (newly created or already existing)
        obj.MemMap = memmapfile( obj.FilePath, 'Writable', true, ...
            'Format', mapFormat );

    end
    
    function assignDataSize(obj)
        
        obj.DataSize = obj.MetaData.Size(1:2);
        obj.DataDimensionArrangement = 'YX';
                
        numChannels = 1; % Todo: Add this from metadata.
        numPlanes = 1; % Todo: Add this from metadata.
        numTimepoints = obj.MetaData.Size(3);
        
        % Add length of channels if there is more than one channel
        if numChannels > 1
            obj.DataSize = [obj.DataSize, numChannels];
            obj.DataDimensionArrangement(end+1) = 'C';
        end
        
        % Add length of planes if there is more than one plane
        if numPlanes > 1
            obj.DataSize = [obj.DataSize, numPlanes];
            obj.DataDimensionArrangement(end+1) = 'Z';
        end
        
        % Add length of sampling dimension.
        if numTimepoints > 1
            obj.DataSize = [obj.DataSize, numTimepoints];
            obj.DataDimensionArrangement(end+1) = 'T';
        end

    end
    
    function assignDataType(obj)
        obj.DataType = obj.MetaData.Class;
    end
    
end

methods % Implementation of abstract methods

    function data = readData(obj, subs)
        data = obj.MemMap.Data.ImageArray(subs{:});
    end
    
    function data = getFrame(obj, frameInd, subs)
        data = obj.getFrameSet(frameInd, subs);
    end
    
    function data = getFrameSet(obj, frameInd, subs)
        
        if nargin < 3
            subs = obj.frameind2subs(frameInd);
        end
        
        data = obj.MemMap.Data.yxt(subs{:});
    end
    
    function writeFrameSet(obj, data, frameInd, subs)
        % Todo: Can I make order of arguments equivalent to upstream
        % functions?
        
        if nargin < 4
            numDims = ndims(obj);
            subs = cell(1, numDims);
            subs(1:end-1) = {':'};
            subs{end} = frameInd;
        end
        
        obj.MemMap.Data.yxt(subs{:}) = data;
        
    end
    
end

methods % Methods for reading/writing configuration file
    
    function S = readinifile(obj)

        % todo: generalize? struct2ini fileex??? checkout readstruct and
        % writestruct
        
        % Get name of inifile
        iniPath = strrep(obj.FilePath, '.raw', '.ini');

        % Read inifile
        iniString = fileread(iniPath);

        % Determine start of and end of lines
        endOfLine = cat(2, regexp(iniString, '\n') );
        startOfLine = cat(2, 1, endOfLine(1:end-1)+1);

        S = struct;

        for i = 1:numel(startOfLine)

            varLine = iniString(startOfLine(i):endOfLine(i)-1);
            varLineSplit = regexp(varLine, '\ = |\"', 'split');
            varName = strtrim(varLineSplit{1});

            switch varName
                case 'Size'
                    varVal = varLineSplit{2};
                    varVal = strsplit(varVal, ' ');
                    varVal = arrayfun(@(x) str2double(x), varVal);
                case 'Class'
                    varVal = strtrim(varLineSplit{2});
                otherwise
                    varVal = strtrim(varLineSplit{2});
            end

            S.(varName) = varVal;

        end
    end

    function writeMetaVariable(obj, varName, varValue)
        % Get name of inifile
        iniPath = strrep(obj.FilePath, '.raw', '.ini');

        if ispc
            fid = fopen(iniPath, 'at');
        else
            fid = fopen(iniPath, 'a');
        end
        
        if ~isa(varValue, 'char')
            if islogical(varValue) || isinteger(varValue)
                varValue = num2str(a);
            elseif isnumeric(varValue)
                varValue = num2str(a, '%.6f');
            else
                error('Not supported yet')
            end
            
        end
        fprintf(fid, '%s = %s\n', varName, varValue);

        fclose(fid);
        
    end
    
    function varValue = readMetaVariable(obj, varName)
        % Get name of inifile
        iniPath = strrep(obj.FilePath, '.raw', '.ini');
        
        % Read inifile
        iniString = fileread(iniPath);
        expression = sprintf('%s = ', varName);

        variableStrLocA = regexp(iniString, expression);
        endOfLines = cat(2, regexp(iniString, '\n') );
        
        isEndOfThisLine = find( endOfLines > variableStrLocA, 1, 'first');
        variableStrLocB = endOfLines(isEndOfThisLine);
        
        thisLine = iniString(variableStrLocA:variableStrLocB);
        
        splitStr = strsplit(thisLine, '=');
        try
            varValue = eval(strrep(splitStr{2}, '\n', ''));
        catch
            varValue = strrep(splitStr{2}, '\n', '');
        end
    end
end

methods (Static)
    
    function TF = writeinifile(filePath, S)

        % todo: generalize?
        
        assert(isfield(S, 'Size'), 'Size input is missing')
        assert(isfield(S, 'Class'), 'Class input is missing')

        % Get name of inifile
        iniPath = strrep(filePath, '.raw', '.ini');

        if ispc
            fid = fopen(iniPath, 'wt');
        else
            fid = fopen(iniPath, 'w');
        end

        fieldNames = fieldnames(S);

        for i = 1:numel(fieldNames)
            switch fieldNames{i}
                case 'Size'
                    fprintf(fid, '%s = %s\n', 'Size', num2str(S.Size));
                case 'Class'
                    fprintf(fid, '%s = %s\n', 'Class', S.Class);
            end
        end
        
        % Todo: Add some error handling here.
        TF = true;

        fclose(fid);

        if ~nargout 
            clear TF
        end
        
    end
    
    function initializeFile(filePath, arraySize, arrayClass)
    
        S = struct('Size', arraySize, 'Class', arrayClass);

        % Create file if it does not exist
        if ~exist(filePath, 'file')
            assert(isfield(S, 'Size'), 'Size input is missing')
            assert(isfield(S, 'Class'), 'Class input is missing')
            
            % Todo: Make this function part of the utility package?
            stack.io.fileadapter.Raw.writeinifile(filePath, S)

            nNumEntries = prod(S.Size);

            switch(lower(S.Class))
                case {'int8', 'uint8', 'logical'}
                    nBytes = 1;
                case {'int16', 'uint16', 'char'}
                    nBytes = 2;
                case {'int32', 'uint32', 'single'}
                    nBytes = 4;
                case {'int64', 'uint64', 'double'}
                    nBytes = 8;
                otherwise
                    error('Unknown Class %s', S.Class);
            end

            nNumEntries = nNumEntries*nBytes;

            if ispc
                [status, ~] = system(sprintf('cmd /C fsutil file createnew %s %i', filePath, nNumEntries));
            elseif ismac
                status = 1;
            end

            if status % Backup solution
                fileId = fopen(filePath, 'w');
                fwrite(fileId, 0, 'uint8', nNumEntries-1);
                fclose(fileId);
            end

        else
            fprintf('Binary file already exists: %s\n', filePath)
        end

    end
    
end 

end