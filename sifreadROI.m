%SIFREADROI Read ROI signal from SIF multi-channel image file.
%
% This version works with Andor Solis version 4.25.30007.0
%
% This function reads a the data from a given ROI region and outputs the average signal intensity trace and optionally the imagedata of the ROI as well.

% This function can read a kinetic data file.

% 22.01.2020
% By Teo Puig Walz and adapted from sifreadnk function by Marcel Leutenegger � November 2006

%Synopsis:
%
%  data=sifread(file)
%     Read the image data from file.
%     Return the image data in the following structure.   
%      
%  .temperature            CCD temperature [�C]
%  .delayExpPeriod         delay after trigger [s]
%  .exposureTime           Exposure time [s]
%  .cycleTime              Time per full image take [s]
%  .accumulateCycles       Number of accumulation cycles
%  .accumulateCycleTime    Time per accumulated image [s]
%  .stackCycleTime         Interval in image series [s]
%  .pixelReadoutTime       Time per pixel readout [s]
%  .detectorType           CCD type
%  .detectorSize           Number of read CCD pixels [x,y]
%  .fileName               Original file name
%  .shutterTime            Time to open/close the shutter [s]
%  .frameAxis              Axis unit of CCD frame
%  .dataType               Type of image data
%  .imageAxis              Axis unit of image
%  .imageArea              Image limits [x1,y1,first image;
%                                        x2,y2,last image]
%  .frameArea              Frame limits [x1,y1;x2,y2]
%  .frameBins              Binned pixels [x,y]
%  .timeStamp              Time stamp in image series
%  .imageData              Image data (x,y,t) where t is the image # for a
%                          kinetic series
%  .kineticLength          number of images in kinetic series


% MAIN FUNCTION
function data = sifreadROI(file,range, rangeType, ROI_position, only_signal)
    % range: [frame_start, frame_end] or [] if all file has to be read
    % rangeType: 1 = read all file
    %            2 = range specified by frame number
    %            3 = range specified by time
    % ROi_info: [Xmin Ymin Width height]

    f=fopen(file,'r');
    if f < 0
       error('Could not open the file.');
    end
    if ~isequal(fgetl(f),'Andor Technology Multi-Channel File')
       fclose(f);
       error('Not an Andor SIF image file.');
    end
    skipLines(f,1); 
    data=readSection(f,range, rangeType, ROI_position, only_signal);
    fclose(f);


%Read a file section.
%
% f      File handle 
% info   Section data
% next   Flags if another section is available
%
function info=readSection(f,range,rangeType, ROI_position, only_signal)
    o=fscanf(f,'%d',6); %% scan over the 6 Bytes
    info.temperature=o(6); %o(6)
    skipBytes(f,10);%% skip the space (why 10 not 11?)

    o=fscanf(f,'%f',5);%% Scan the next 5 bytes
    info.delayExpPeriod=o(2);
    info.exposureTime=o(3);
    info.accumulateCycles=o(5);
    info.accumulateCycleTime=o(4);
    skipBytes(f,2); %% skip 2 more bytes
    o=fscanf(f,'%f',2);
    info.stackCycleTime=o(1);
    if info.stackCycleTime == 0 % addition for tif converted to sif - Callum ZJ
        fps_int = inputdlg('Enter fps:','Frame rate',[1 35],{'100'});
        info.stackCycleTime = 1./str2double(fps_int(1));
    end
    info.pixelReadoutTime=o(2);
    o=fscanf(f,'%d',3);
    info.gainDAC=o(3);
    skipLines(f,1);
    info.detectorType=readLine(f);

    info.detectorSize=fscanf(f,'%d',[1 2]); %% I think everythings ok to here
    info.fileName=readString(f);
    %skipLines(f,4); %% changed this from 26 from Ixon camera now works for Newton. %%%%%%%%%%%%%%%%%%%%%%% ALL YOU NEED TO CHANGE

    skipUntil(f,'65538')
    skipUntil(f,'65538')

    % Added the following to extract the center wavelength and grating
    o=fscanf(f,'%f',8);
    info.centerWavelength = o(4);
    info.grating = round(o(7));

    %skipLines(f,10); % added this in 
    skipUntil(f,'65539')
    skipUntil(f,'65538') %NEW
    backOneLine(f) %NEW
    o=fscanf(f,'65538 %d %d %d %d %d %d %d %d 65538 %d %d %d %d %d %d',14);
    if o(2) == 0
        split = 1;
    else
        split = 0;
    end


    skipUntilChar(f,'.')
    backOneLine(f)

    o=fscanf(f,'%f',4);
    info.minWavelength = o(1);
    info.stepWavelength = o(2);
    info.step1Wavelength = o(3);
    info.step2Wavelength = o(4);
    info.maxWavelength = info.minWavelength + info.detectorSize(1)*info.stepWavelength;

    % Create wavelength, energy and frequency axes.
    da = 1:(info.detectorSize(1));
    info.axisWavelength = info.minWavelength + da.*(info.stepWavelength + da.*info.step1Wavelength + da.^2*info.step2Wavelength);
    info.axisEnergy = convertUnits(info.axisWavelength,'nm','eV'); % energy in eV
    info.axisGHz = convertUnits(info.axisWavelength,'nm','GHz');

    %skipUntil(f,'Wavelength');
    %backOneLine(f)
    %backOneLine(f)

    skipUntil(f,'Pixel number')
    backOneLine(f)
    skip = fscanf(f,'%12c',1);
    info.frameAxis = fscanf(f,'%d',1); %'Pixel number' 

    skip = fscanf(f,'%7c',1);
    info.dataType = fscanf(f,'%d',1);  %'Counts' %% gets this from andor file

    skip = fscanf(f,'%13c',1);
    o=fscanf(f,'65541 %d %d %d %d %d %d %d %d 65538 %d %d %d %d %d %d',14); %% 14 is lines in o?
    temp = o;
    info.imageArea=[o(1) o(4) o(6);o(3) o(2) o(5)];
    info.frameArea=[o(9) o(12);o(11) o(10)];
    info.frameBins=[o(14) o(13)];
    s=(1 + diff(info.frameArea))./info.frameBins;
    z=1 + diff(info.imageArea(5:6));
    info.height = s(2);
    info.width = s(1);
    info.kineticLength = o(5);
    %Teo: I had to comment out this lines to read large datasets. It works even if inconsistent image header
    %if prod(s) ~= o(8) || o(8)*z ~= o(7)
    %   fclose(f);
    %   error('Inconsistent image header.');
    %end
    % for n=1:z                       % Had to comment this section for kinetic
    %    o=readString(f);
    %    if numel(o)
    %       fprintf( '%s\n',o);      % comments
    %    end
    % end

    if split == 0
        skipLines(f,2+2*info.kineticLength); % changed from 2 to 2+info.kineticLength. This is the trick to get kinetic mode to work.
    else
        skipLines(f,2+info.kineticLength); % changed from 2 to 2+info.kineticLength. This is the trick to get kinetic mode to work.
    end

    fps = 1/info.stackCycleTime;
    % IMAGE DATA SECTION COMES NOW
    % ---------------------------------------------------------------------------------------------
    if rangeType == 1 % read all file
        start_frame = 1;
        end_frame = info.kineticLength;
        
    elseif rangeType == 2
        start_frame = range(1);
        end_frame = range(2);
   
    elseif rangeType == 3
        start_frame = floor(range(1)*fps)+1;
        end_frame = floor(range(2)*fps)+1;
    end

    total_length = (end_frame-start_frame)+1;
    
    %Find how many bytes correspond to the frames previous the section we want
    pxls_per_frame = info.height*info.width;
    skip_pxls = pxls_per_frame*(start_frame-1);
    skip_bytes = skip_pxls*4; %single precision values that are read have 4 bytes
    % Skip the bytes of the frames we are not interested in
    status = fseek(f, skip_bytes ,'cof');

    roi_xmin = ROI_position(1)-1;
    roi_ymin = ROI_position(2)-1;
    roi_width = ROI_position(3);
    roi_height = ROI_position(4);

    % Read section we are interested in
    % Important pixel number information (multiply by 4 to obtain number of bytes!)
    NN = info.width; %Pixels per line without ROI
    L_N1 = roi_ymin; % Lines previous ROI lines (above)
    L_R = roi_height; % Lines that include ROI pixels
    L_N2 = info.height - (L_N1 + L_R); % Lines after ROI lines (below). 
    nn = roi_width; % pixels of ROI in one line
    alpha = roi_xmin; % pixels in one line previous to the roi pixels.
    beta = info.width - (roi_xmin + roi_width); %pixels in one line after roi pixels

    info.ROI_signal = zeros(2,total_length); % first row is time vector and second row is signal vector
    
    if ~only_signal % If not only signal, generate a matrix to store the ROI area data
        info.ROI = zeros(roi_height, roi_width, total_length); %would need to flip updown and permute if all frames are taken
    end
    
    % 1. For every frame  ROI
    for frame=1:total_length
        %disp(['Reading frame ',num2str(frame)])

        % 2. Skip lines below the ROI - Y axis on images is inverted in matlab compared to camera (0,0) is top left in matlab while its bottom left on the camera!
        skip = fseek(f, L_N2*NN*4 ,'cof');

        % 3. Read ROI lines
        ROI_frame = ones(1,L_R); %each element of the vector is the mean of each line of the ROI

        for k=1:L_R
            %disp(['Reading ROI line ', num2str(k)])
            % 3.1. Skip alpha  pixels previous to roi within the ROi line
            skip = fseek(f, alpha*4 ,'cof');

            % 3.2. READ LINE PIXELS OF THE ROI
            ROI_line = fread(f,nn,'single=>single'); %fread has the input in pixels not bytes
            ROI_frame(k) = mean(ROI_line);
            
            if ~only_signal
                info.ROI(k, :,frame) = ROI_line; 
            end

            % 3.4. Skip beta pixels in the line after the ROI
            skip = fseek(f, beta*4 ,'cof');

        end

        info.ROI_signal(2,frame) = mean(ROI_frame);

        % 4. Skip lines without ROi above the ROI (L_N2)
        skip = fseek(f, L_N1*NN*4 ,'cof');

    end        

    time = [0: 1/fps: (total_length-1)/fps];
    info.ROI_signal(1,:)  = time;
    
    if ~only_signal
        info.imageData = flipud(info.ROI);
    end








%Read a character string.
%
% f      File handle
% o      String
%
function o=readString(f)
    n=fscanf(f,'%d',1);
    if isempty(n) || n < 0 || isequal(fgetl(f),-1)
       fclose(f);
       error('Inconsistent string.');
    end
    o=fread(f,[1 n],'uint8=>char');


%Read a line.
%
% f      File handle
% o      Read line
%
function o=readLine(f)
    o=fgetl(f);
    if isequal(o,-1)
       fclose(f);
       error('Inconsistent image header.');
    end
    o=deblank(o);


%Skip bytes.
%
% f      File handle
% N      Number of bytes to skip
%
function skipBytes(f,N)
    [ret,n]=fread(f,N,'uint8');
    if n < N
       fclose(f);
       error('Inconsistent image header.');
    end


%Skip lines.
%
% f      File handle
% N      Number of lines to skip
%
function skipLines(f,N)
    for n=1:N
       if isequal(fgetl(f),-1)
          fclose(f);
          error('Inconsistent image header.');
       end
    end





% Skip to the line starting with str.

function skipUntil(f,str)

    ls = length(str);
    stringFound = 0;
    while ~stringFound
        % Read line
        s = readLine(f);

        if length(s)>=ls && strcmp(s(1:ls), str) % check if string found.
            stringFound = 1;
        else
            stringFound = 0;        
        end
    end

% Skip to the first incidence of the character c.
function skipUntilChar(f,c)
    stringFound = 0;
    while ~stringFound
        % Read line
        cread=fscanf(f,'%c',1);
        if cread==c
            stringFound=1;
        end
    end


function backOneLine(f)
    newLineFound = 0;
    numTimes = 0;
    while ~newLineFound
        fseek(f,-2,'cof');
        c=fscanf(f,'%c',1);
        newLineFound = c==10;
        numTimes = numTimes+1; 
    end
% 
% if numTimes<=2
% fseek(f,-4,'cof');
% numTimes = 0;
% while ~newLineFound
%     fseek(f,-2,'cof');
%     c=fscanf(f,'%d',1)
%     newLineFound = c==10;
%     numTimes = numTimes+1; 
% end
% end