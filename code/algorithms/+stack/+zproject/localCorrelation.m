function im = localCorrelation(imArray, dim)

    if ndims(imArray) > 3
        error('Not implemented for matrices with more than 3 dims'); 
    end


    numRows = 4;
    numCols = 4;
    showWaitbar = true;
    

    getChunkedData = @stack.reshape.imsplit;
    tmpIm = getChunkedData(imArray, true, [], 'numRows', numRows, 'numCols', numCols);
    
    tmpC = cell(size(tmpIm));

    if showWaitbar
        h = waitbar(0, 'Calculating neighbor correlation');
    end
    
    P = double( prctile(single(imArray(:)), [0.5, 99.5]) );
    
    
    numIter = numRows .* numCols;
    currentIter = 0;
    
    for i = 1:numRows
        for j = 1:numCols
            
            %Credit: Eftychios A. Pnevmatikakis & Pengcheng Zhou
            correlation_image = @stack.process.compute.correlation_image;
            tmpC{i, j} = correlation_image(single(tmpIm{i,j}));
            
            currentIter = currentIter+1;
            if showWaitbar
                waitbar(currentIter/numIter, h)
            end
            
        end
    end

    [d1,d2,~] = size(imArray);
    cIm = getChunkedData(tmpC, false, [d1,d2,1], 'numRows', 4, 'numCols', 4);
    %cIm = stack.makeuint8(cIm);
    
    cIm = cIm .* range(P) + P(1);
    cIm = cast(cIm, class(imArray));
    
        if showWaitbar
            close(h)
        end
    
    im = cIm;

end