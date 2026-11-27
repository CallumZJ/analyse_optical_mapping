% Return the data in a .dat file as a three-dimensional array 
% (image sequence), where the third coordinate is the frame number.
%
% v = OPREAD(file) returns the whole .dat file as a uint16 matrix.
% v = OPREAD(file, options) uses the structure options
%       .fromFrame     - number of the first frame to read
%       .toFrame       - number of the last frame to read
%       .fromX         - number of the first column to read
%       .toX           - number of the last column to read
%       .fromY         - number of the first row to read
%       .toY           - number of the last row to read
%       .machineformat - machineformat to be used for reading from the file
%       .precision     - returns the matrix as array of class 'precision'
% 
% Pixel and frame numbers can be specified with normal positive indices
% starting at 1, or with negative indices starting at 0 which corresponds
% to the greatest posssible index.
%
% [v,h] = OPREAD(...) returns also the header structure obtained from
%                     OPHEADER().
%
% [v,h,times] = OPREAD(...) returns also the times of exposure for each 
%                           frame as a cell-array of strings (versions E)
%                           or as a row vector of type uint64 (version F).
%
% Based on files written by Martin, Cornell University, 2005.
% Various modifications by Stefan Luther and Amgad Squires, 2006-2009.
% Unification and version F by Johannes Schroeder-Schetelig, 2010-01-12.
%
% Modified by T Alexander Quinn, 2013-01-16, based on old_modified_opread:
%
% [images,header,times] = new_modified_opread(file,first_frame,last_frame,first_x_pixel,last_x_pixel,first_y_pixel,last_y_pixel,flip_image_choice)
% Returns a set of images as a matrix for the chosen frames, the chosen pixels, 
% and flipped to the desired conformation.

function [images,header,times] = dat_reader(file,range, rangeType)

if (nargin<1)
    error('Too few arguments. OPREAD requires at least a file name.');
end

machineformat = 'l';
header = dat_header_reader(file,machineformat);
precision = 'uint16';

if (header.version~='a' && header.version~='c' && header.version~='d' && header.version~='e' && header.version~='f')
    error('"%c" is not a recognized version.',header.version);
end

ncol = header.sizeX;
nrow = header.sizeY;

xbin = header.binX;
ybin = header.binX;

if rangeType == 1 %read all file
    first_frame = 10;
    last_frame = header.frames;
elseif rangeType == 2 % read partial file. Range specified by frame numbers
    first_frame = range(1);
    last_frame = range(2);
elseif rangeType ==3 % read partial file. Range specified by time
    fps = 1/header.acquisitionFrequency;
    first_frame = floor(range(1)*fps)+1;
    last_frame = floor(range(2)*fps)+1;
end

first_x_pixel = 1;
last_x_pixel = header.sizeX;
first_y_pixel = 1;
last_y_pixel = header.sizeY;



ncol_read = last_x_pixel - first_x_pixel + 1;
nrow_read = last_y_pixel - first_y_pixel + 1;
% 
read_first_x_pixel = first_y_pixel;
read_last_x_pixel = last_y_pixel;
read_first_y_pixel = ncol - (last_x_pixel - 1);
read_last_y_pixel = ncol - (first_x_pixel - 1);

clear fid
[fid,msg] = fopen(file,'rb',header.machineformat);
if fid == -1
   error('Cannot open file %s -> %s',file,msg);
end

fseek(fid, 1024, 'bof'); % skip header

if (header.version == 'e')
	fseek(fid, 6*first_frame-1, 'cof');
	times = {};
	for i = 1:last_frame-first_frame+1
		str = transpose(fread(fid, 6, 'int8=>char'));
	    times = [times str];
	end
	fseek(fid, 1024+6*header.frames, 'bof');
end

% preallocate memory:

if (header.version == 'f')
	times = zeros(1, last_frame-first_frame+1, 'uint64');
end

images = zeros(last_y_pixel-first_y_pixel+1, last_x_pixel-first_x_pixel+1, ...
		  last_frame-first_frame+1, precision);
	  
fseek(fid, header.blockSize*(first_frame-1), 'cof'); % skip first blocks


for loop = 1:(last_frame-first_frame+1)         
	image = fread(fid, [header.sizeX, header.sizeY], '*uint16'); 
	image = image'; % Data comes out transposed.
	image(1,1) = 65535;
   
    image=rot90(image,1);
    
	image = image(first_y_pixel:last_y_pixel, first_x_pixel:last_x_pixel); % Trim the image to the desired dimensions.
	images(:,:,loop) = cast(image, precision); % Write the result as the next frame in the data matrix.
	if header.version == 'f'
        times(loop) = fread(fid, 1, '*uint64');
    end
    

end

images(end,1,1) = NaN;

fclose(fid);
return;
