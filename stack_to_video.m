function stack_to_video(stack, file_name, file_path, time_info, options)

%% Stack to video function using ffmpeg
% Callum Zgierski-Johnston
% 28.03.2023
% Inputs:
% stack: stack to be saved
% file_name: file name to be saved to
% time_info: consists of the possible options for the time stamp that can be changed as name-value pairs.
%   These are: 
%       timestamp: whether to display a time stamp (1,0 [default])
%       position: position of the time stamp in pixels (default [1,1])
%       step_size: size of the time step (default 0.001 s)
%       units: units to display the timestep as ('s' [default],'ms','us','ns')
%       precision: to which to display info (default 3)
%       font: font to use (default 'Arial')
%       font_color: font colour to use (default 'white')
%       font_size: font size to use (default 10)
%       box_color: default background box color (default 'black')
%       opacity: opacity of box from 0 to 1 (default 0, i.e. no box)
% options: consists of the possible options that can be changed as name-value pairs.
%   These are:
%      fps: output frames per second (default 24)
%       quality: output quality from 0 to 10 (default 5) 
%       cMap - colour map for saving


%% Argument validation
arguments
    stack {mustBeNumeric}
    file_name string
    file_path string = pwd
    time_info.timestamp (1,1) {mustBeNumeric,mustBeReal} = 0
    time_info.position (1,2) {mustBeNumeric,mustBeReal} = [1,1]
    time_info.step_size (1,1) {mustBeNumeric,mustBeReal} = 0.001
    time_info.units string = 's'
    time_info.precision (1,1) {mustBeNumeric,mustBeReal} = 3
    time_info.font string = 'Arial'
    time_info.font_color string = 'white'
    time_info.font_size (1,1) {mustBeNumeric,mustBeReal} = 10
    time_info.box_color string = 'black'
    time_info.opacity (1,1) {mustBeNumeric,mustBeReal} = 0
    options.fps (1,1) {mustBeNumeric,mustBeReal} = 24
    options.quality (1,1) {mustBeNumeric,mustBeReal} = 5    
    options.cMap (:,3) {mustBeNumeric,mustBeReal} = hot(256);
end

%% Generate images for saving
if file_path == ''
    temp_folder_path = strcat(pwd,'\ffmpeg_temp');
else
    temp_folder_path = strcat(file_path,'\ffmpeg_temp');
end
mkdir(temp_folder_path);

% Convert image stack ready for converting frames to rgb
cMapSize = size(options.cMap,1);
stack_rgb = round(cMapSize*stack/max(stack(:)));

% Zero pad to ensure width and height are divisible by 2
if rem(size(stack_rgb,1),2) ~= 0
    stack_rgb = padarray(stack_rgb,[1,0,0],'pre');
end
if rem(size(stack_rgb,2),2) ~= 0
    stack_rgb = padarray(stack_rgb,[0,1,0],'pre');
end

if size(time_info.font_color) == [1,3]
    time_info.font_color = double(time_info.font_color);
end

for k = 1:size(stack,3)
    % Convert frame to RGB
    frame_rgb = ind2rgb(stack_rgb(:,:,k),options.cMap);

    % Add timestamp if it's selected.
    if time_info.timestamp == 1
        switch time_info.units
            case 's'
                time = sprintf('%.*f s', time_info.precision, (k-1)*time_info.step_size); 
            case 'ms'
                time = sprintf('%.*f ms', time_info.precision, (k-1)*time_info.step_size*1e3);
            case 'us'
                time = sprintf('%.*f μs', time_info.precision, (k-1)*time_info.step_size*1e6);
            case 'ns'
                time = sprintf('%.*f ns', time_info.precision, (k-1)*time_info.step_size*1e9);
        end

        frame_rgb = insertText(frame_rgb, time_info.position, time,'AnchorPoint','LeftBottom','Font',time_info.font,'TextColor',time_info.font_color,'FontSize',time_info.font_size,'BoxColor',time_info.box_color,'BoxOpacity',time_info.opacity);
    end

    imwrite(frame_rgb,sprintf('%s\\%0*d.png',temp_folder_path,ceil(log10(size(stack,3)))-1,k));
end

%% Perform ffmpeg
% Convert quality into crf
quality = 30-options.quality*1.5;
sp = {' '};
if file_path == ''
    output = system(strcat('ffmpeg -r',sp,num2str(options.fps),sp,'-f image2 -i "',temp_folder_path,'\%0',num2str(ceil(log10(size(stack,3)))-1),'d.png" -vcodec libx264 -crf',sp,num2str(quality),sp,'-pix_fmt yuv420p "',file_name,'.mp4"'));
else
    output = system(strcat('ffmpeg -r',sp,num2str(options.fps),sp,'-f image2 -i "',temp_folder_path,'\%0',num2str(ceil(log10(size(stack,3)))-1),'d.png" -vcodec libx264 -crf',sp,num2str(quality),sp,'-pix_fmt yuv420p "',file_path,'\',file_name,'.mp4"'));
end

%% Tidy up temporary files
rmdir(temp_folder_path,'s');
end

