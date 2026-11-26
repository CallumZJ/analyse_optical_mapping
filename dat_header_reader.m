% OPHEADER(file) returns header information from surface map file.
%
% header = OPHEADER(file) returns a structure with the following fields:
%   .version       - The file version, as a char.
%   .machineformat - Machineformat used for reading from the file.
%   .datetime      - The date and time of the first frame, as a string.
%   .comment       - Comment string.
%   .frames        - number of frames.
%   .sizeX         - Image width.
%   .sizeY         - Image height.
%   .binX          - X binning factor used during recording.
%   .binY          - Y binning factor used during recording.
%   .acquisitionFrequency - Estimated acquisition frequency.
%   .blockSize     - Size of a data block in bytes (image data plus 
%                    additional info like time of exposure in version 'f').
%                    Use this block size to skip the additional info, if
%                    not needed.
%
% OPHEADER(file, machineformat) uses the specified machineformat for
%   reading from the file. Default machineformat = little endian.
%   The machineformat for version 'f' files is determined automatically
%   and returned in header.machineformat
%
% Based on files written by Martin, Cornell University, 2005.
% Various modifications by Stefan Luther and Amgad Squires, 2006-2009.
% Unification and version F by Johannes Schroeder-Schetelig, 2010-01-12.

function header = dat_header_reader(file, machineformat)

if (nargin == 1)
	machineformat = 'l'; % default format = little endian
end
if (nargin == 0)
	error('Too few arguments.');
end
if (nargin > 2)
	error('Too many arguments.');
end

[fid,msg] = fopen(file,'rb',machineformat);
if fid<0
   error('Cannot open file %s -> %s',file,msg);
end

version = fread(fid,1, 'int8=>char');


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% VERSION A
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

switch version
case 'a'
    datetime = fread(fid, 20, 'int8=>char');
    datetime = transpose(datetime);
    frames= fread(fid, 1, '*double');
    sizeY= fread(fid, 1, '*double');
    sizeX= fread(fid, 1, '*double');
    flag=0;
    comment='';
    fseek(fid, 1, 0);
	while ~flag
        x = fread(fid, 1, 'int8=>char');
        if (x==3) 
			flag=1;
		else
			comment = [comment x];
        end
	end

	binX = 1.0;
	binY = 1.0;
	acquisitionFrequency = 0.0;
    blockSize = 2*sizeX*sizeY;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% VERSION C
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

case 'c'
    datetime = fread(fid, 17, 'int8=>char');
    datetime = transpose(datetime);
    frames= fread(fid, 1, '*int32');
    sizeY= fread(fid, 1, '*int32');
    sizeX= fread(fid, 1, '*int32');
    flag=0;
    comment='';
    fseek(fid, 1, 0);
	while ~flag
        x = fread(fid, 1, 'int8=>char');
        if (x==3) 
			flag=1;
		else
			comment = [comment x];
        end
	end
	
	frames = double(frames);
	sizeX = double(sizeX);
	sizeY = double(sizeY);
	binX = 1.0;
	binY = 1.0;
	acquisitionFrequency = 0.0;
    blockSize = 2*sizeX*sizeY;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% VERSION D and E
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

case {'d', 'e'}
    
    datetime = fread(fid, 17, 'int8=>char');  %early files are 17, later are 24
    % if date string begins with an alphabet character ('A' = 65) then the
    % date string is 24 characters long and thus 7 more need to be read.
    if datetime(1) >= 65
        datetime = [datetime; fread(fid, 7, 'int8=>char')];
    end
    datetime = transpose(datetime);
    frames = fread(fid, 1, '*int32');
    sizeY = fread(fid, 1, '*int32');
    sizeX = fread(fid, 1, '*int32');
    binX = fread(fid, 1, '*int32');
    binY = fread(fid, 1, '*int32');
    flag=0;
    comment='';
    fseek(fid, 1, 0);
	while ~flag
        x = fread(fid, 1, 'int8=>char');
        if (x==3) 
			flag=1;
		else
			comment = [comment x];
        end
	end
	
	frames = double(frames);
	sizeX = double(sizeX);
	sizeY = double(sizeY);
	binX = double(binX);
	binY = double(binY);
	acquisitionFrequency = 0.0;
    blockSize = 2*sizeX*sizeY;


    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% VERSION F
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

case 'f'
	% Automatic byte order detection:
	fclose(fid);
	machineformat = 'l';
	fid = fopen(file,'rb',machineformat); % reopen file with little endian format
	fseek(fid, 1, 'bof'); % skip version
    byteOrderMark = fread(fid, 1, '*uint32');
	if (byteOrderMark ~= uint32(hex2dec('1A2B3C4D'))) % wrong format
		fclose(fid);
		machineformat = 'b';
		fid = fopen(file,'rb',machineformat); % reopen file with big endian format
		fseek(fid, 1, 'bof'); % skip version
		byteOrderMark = fread(fid, 1, '*uint32');
		if (byteOrderMark ~= uint32(hex2dec('1A2B3C4D'))) % still wrong format
			fclose(fid);
			error('Unrecognized byte order.');
		end
	end	
		
	frames = fread(fid, 1, '*uint32');
	sizeX = fread(fid, 1, '*uint32');
	sizeY = fread(fid, 1, '*uint32');
	binX = fread(fid, 1, '*uint32');
	binY = fread(fid, 1, '*uint32');
	acquisitionFrequency = fread(fid, 1, '*uint32');
	datetime = fread(fid, 24, 'int8=>char'); % read date string
	datetime = transpose(datetime(1:23)); % trim the 0-character and convert to a matlab string
	% read null-terminated comment string:
	comment = '';
	ch = fread(fid, 1, 'int8=>char');
	while ch ~= 0
		comment = [comment ch];
		ch = fread(fid, 1, 'int8=>char');
	end

	frames = double(frames);
	sizeX = double(sizeX);
	sizeY = double(sizeY);
	binX = double(binX);
	binY = double(binY);
	acquisitionFrequency = double(acquisitionFrequency) * 1e-3;
    blockSize = 2*sizeX*sizeY + 8;

otherwise
    error('"%c" is not a recognized version.',version);
end

fclose(fid);

header.version = version;
header.machineformat = machineformat;
header.datetime = datetime;
header.comment = comment;
header.frames = frames;
header.sizeX = sizeX;
header.sizeY = sizeY;
header.binX = binX;
header.binY = binY;
header.acquisitionFrequency = acquisitionFrequency;%/10; %Teo: modified this to match real fps, not sure why though
header.blockSize = blockSize;

return;