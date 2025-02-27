classdef Session < nansen.metadata.abstract.BaseSchema
%Session A generic metadata schema for an experimental session.
%
%
%   This class provides general metadata about an experimental session and
%   methods for accessing experimental data.



%   Questions: 
%       - Is it better to have get/create session folders as methods in
%           DataLocations (the model)

%   Todo:
%       [ ] Implement methods for saving processing/analysis results to
%           multiple times based on timestamping...
%       [ ] Spin off loadData/saveData to a separate class (superclass)
%       [ ] Implement save method... If changes are made, they need to be
%           saved to file... But also table.....
%       
    

    % Implement superclass abstract property
    properties (Constant, Hidden)
        IDNAME = 'sessionID'
    end

    
    properties
        
        % Unique identification properties.
        subjectID      % Add some validation scheme.... Can I dynamically set this according to whatever?
        sessionID    char
               
        IgnoreFlag = false

        % Date and time for experimental session
        Date
        Time
        
        % Experimental descriptions
        Experiment char     % What experiment does the session belong to.
        Protocol char       % What is the name of the protocol
        Description char    % A description of the session

        DataLocation struct % Where is session data stored
        Progress struct     % Whats the pipeline status / progress
        
    end
    
    
    methods % Assign metadata
            
        function assignSubjectID(obj, pathStr)
            % Get specification for how to retrieve subject id from
            % datalocation..
            global dataLocationModel
            if isempty(dataLocationModel); return; end
            
            subjectId = dataLocationModel.getSubjectID(pathStr);
            obj.subjectID = subjectId;
        end
        
        function assignSessionID(obj, pathStr)
            % Get specification for how to retrieve session id from
            % datalocation..
            
            global dataLocationModel
            if isempty(dataLocationModel); return; end

            sessionId = dataLocationModel.getSessionID(pathStr);
            obj.sessionID = sessionId;
            
        end
        
        function assignTimeInfo(obj, pathStr)
            % Get specification for how to retrieve time info from
            % datalocation..
            
            global dataLocationModel
            if isempty(dataLocationModel); return; end

            obj.Time = dataLocationModel.getTime(pathStr);
        end
        
        function assignDateInfo(obj, pathStr)
            % Get specification for how to retrieve time info from
            % datalocation..
            
            global dataLocationModel
            if isempty(dataLocationModel); return; end

            obj.Date = dataLocationModel.getDate(pathStr);

        end
        
    end
    
    
    methods % Load data variables

        function data = loadData(obj, varName, varargin)
            
            % TODO:
            %   [ ] Implement file adapters.
            
            filePath = obj.getDataFilePath(varName, '-r', varargin{:});
            
            if isfile(filePath)
                S = load(filePath, varName);
                if isfield(S, varName)
                    data = S.(varName);
                else
                    error('File does not hold specified variable')
                end
            else
                error('File not found')
            end
            
        end
        
        
        function saveData(obj, varName, data, varargin)
            
            % TODO:
            %   [ ] Implement file adapters.
            
            filePath = obj.getDataFilePath(varName, '-w', varargin{:});
            
            S.(varName) = data;
            save(filePath, '-struct', 'S')
            
        end
        
        
        function pathStr = getDataFilePath(obj, varName, varargin)
        %getDataFilePath Get filepath to data within a session folder
        %
        %   pathStr = sessionObj.getDataFilePath(varName) returns a
        %   filepath (pathStr) for data with the given variable name 
        %   (varName).
        %
        %   pathStr = sessionObj.getDataFilePath(varName, mode) returns the
        %   filepath subject to the specified MODE:
        %       '-r'    : Get filepath of existing file (Default)
        %       '-w'    : Get filepath of existing file or create filepath
        %
        %   pathStr = sessionObj.getDataFilePath(__, Name, Value) uses 
        %   name-value pair arguments to control aspects of the filename.
        %
        %   PARAMETERS:
        %
        %       Subfolder : If file is in a subfolder of sessionfolder.
        %
        %
        %   EXAMPLES:
        %
        %       pathStr = sObj.getFilePath('dff', '-w', 'Subfolder', 'roisignals')
        
            
            % Todo: 
            %   [ ] (Why) do I need mode here?
            %   [ ] Implement load/save differences, and default datapath
            %       for variable names that are not defined.
            %   [ ] Implement ways to grab data spread over multiple files, i.e
            %       if files are separate by imaging channel, imaging plane,
            %       trials or are just split into multiple parts...
            
            
            % Get the model for data file paths.
            global dataFilePathModel
            if isempty(dataFilePathModel)
                dataFilePathModel = nansen.setup.model.FilePathSettingsEditor;
            end

            
            % Check if mode is given as input:
            [mode, varargin] = obj.checkDataFilePathMode(varargin{:});
            parameters = struct(varargin{:});
            
            % Get the entry for given variable name from model
            [S, isExistingEntry] = dataFilePathModel.getEntry(varName);
        
            % Get path to session folder
            sessionFolder = obj.getSessionFolder(S.DataLocation);
            
            % Check if file should be located within a subfolder.
            if isfield(parameters, 'Subfolder') && ~isExistingEntry
                S.Subfolder = parameters.Subfolder;
            end
            
            if ~isempty(S.Subfolder)
                sessionFolder = fullfile(sessionFolder, S.Subfolder);
                
                if ~isfolder(sessionFolder) && strcmp(mode, 'write')
                    mkdir(sessionFolder)
                end
            end
            
            
            if isempty(S.FileNameExpression)
                fileName = obj.createFileName(varName, parameters);
            else
                fileName = obj.lookForFile(sessionFolder, S);
                if isempty(fileName)
                    fileName = obj.getFileName(S);
                end
            end
            
            pathStr = fullfile(sessionFolder, fileName);
            
            % Save filepath entry to filepath settings if it did
            % not exist from before...
            if ~isExistingEntry && strcmp(mode, 'write')
                dataFilePathModel.addEntry(S)
            end
            
        end
        
        function [mode, varargin] = checkDataFilePathMode(~, varargin)
            
            % Default mode is read:
            mode = 'read';
            
            if ~isempty(varargin) && ischar(varargin{1})
                switch varargin{1}
                    case '-r'
                        mode = 'read';
                        varargin = varargin(2:end);
                    case '-w'
                        mode = 'write';
                        varargin = varargin(2:end);
                end
            end
            
        end
        
        function fileName = lookForFile(obj, sessionFolder, S)

            % Todo: Move this method to filepath settings editor.
            
            expression = S.FileNameExpression;
            fileType = S.FileType;
            
            if contains(expression, fileType)
                expression = ['*', expression];
            else
                expression = ['*', expression, fileType]; % Todo: ['*', expression, '*', fileType] <- Is this necessary???
            end
            
            L = dir(fullfile(sessionFolder, expression));
            L = L(~strncmp({L.name}, '.', 1));
            
            if ~isempty(L) && numel(L)==1
                fileName = L.name;
            elseif ~isempty(L) && numel(L)>1
                error('Multiple files were found')
            else
                fileName = '';
            end
            
        end
        
        function fileName = createFileName(obj, varName, parameters)
            
            sid = obj.sessionID;
            
            capLetterStrInd = regexp(varName, '[A-Z, 1-9]');

            for i = fliplr(capLetterStrInd)
                if i ~= 1
                    varName = insertBefore(varName, i , '_');
                end
            end
            
            varName = lower(varName);
            
            fileName = sprintf('%s_%s', sid, varName);
            
            if isfield(parameters, 'FileType')
                fileExtension = parameters.FileType;
                if ~strncmp(fileExtension, '.', 1)
                    fileExtension = strcat('.', fileExtension);
                end
            else
                fileExtension = '.mat';
            end
            
            fileName = strcat(fileName, fileExtension);

        end
        
        function fileName = getFileName(obj, S)
            
            sid = obj.sessionID;

            fileName = sprintf('%s_%s', sid, S.FileNameExpression);
            
            fileType = S.FileType;
            
            if ~strncmp(fileType, '.', 1)
                fileType = strcat('.', fileType);
            end
            
            fileName = strcat(fileName, fileType);
            
        end
        
        function folderPath = getSessionFolder(obj, dataLocationType)
        % Get session folder for session given a dataLocationType
        
            % Todo: implement secondary roots (ie cloud directories)
            
            global dataLocationModel
            if isempty(dataLocationModel)
                dataLocationModel = nansen.setup.model.DataLocations();
            end
            
            if isfield(obj.DataLocation, dataLocationType)
                folderPath = obj.DataLocation.(dataLocationType);
            else
                dataLocTypes = {dataLocationModel.Data.Name};
                    
                if ~any( strcmp(dataLocTypes, dataLocationType) )
                    error(['Data location type ("%s") is not valid. Please use one of the following:\n', ...
                           '%s'], dataLocationType, strjoin(dataLocTypes, ', ') )
                else
                    folderPath = obj.createSessionFolder(dataLocationType);
                end
                
            end
            
            if ~isfolder(folderPath)
                error('Session folder not found')
            end
            
        end
        
        function folderPath = createSessionFolder(obj, dataLocationName)
            
            % Get data location model. Question: Better way to do this?
            global dataLocationModel
            if isempty(dataLocationModel)
                dataLocationModel = nansen.setup.model.DataLocations();
            end
            
            S = dataLocationModel.getDataLocation(dataLocationName);
            
            rootPath = S.RootPath{1};
            
            folderPath = rootPath;
            
            for i = 1:numel(S.SubfolderStructure)
                
                switch S.SubfolderStructure(i).Type
                    
                    case 'Animal'
                        folderName = sprintf('subject-%s', obj.subjectID);
                    case 'Session'
                        folderName = sprintf('session-%s', obj.sessionID);
                    case 'Date'
                        folderName = obj.Date;
                    case 'Time'
                        folderName = obj.Time;
                    otherwise
                        folderName = S.SubfolderStructure(i).Name;
                        
                        if isempty(folderName)
                            error('Can not create session folder because foldername is not specified')
                        end
                end
                
                folderPath = fullfile(folderPath, folderName);
                
            end
            
            if ~isfolder(folderPath)
                mkdir(folderPath)
            end
            
            obj.DataLocation.(dataLocationName) = folderPath;
            
            if ~nargout
                clear folderPath
            end

        end
        
    end
    
    
    methods (Static)
                

        
        function S = getMetaDataVariables()
            
            
        end
    end
    
end