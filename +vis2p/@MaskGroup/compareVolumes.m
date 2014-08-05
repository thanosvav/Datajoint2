function compareVolumes(obj,key1,key2)

global data1
global data2
global pointi
global offset
global markId
global xLoc
global yLoc
global ind
global step
global stop

stop = false;
xLoc = 1;
yLoc = 1;
markId = [];
ind = 35;
offset = -24;

import vis2p.*
% AOD
name = fetch1( Experiments*Scans(key1),'file_name' );
if ~strcmp(fetch1(Scans(key1),'aim'),'stack')
    display('Detecting volume..')
    u_ind = strfind(name,'_');
    
    volumename = fetchn(Scans(rmfield(key1,'scan_idx'),[...
        'file_name LIKE "' name(1:u_ind(1)) ...
        '%" and scan_idx > ' num2str(key1.scan_idx -2) ...
        ' and scan_idx < ' num2str(key1.scan_idx + 2) ...
        ' and aim = "Stack"' ...
        ]),'file_name');
    if isempty(volumename)
        volumename = fetchn(Scans(rmfield(key1,'scan_idx'),[...
            'file_name LIKE "' name(1:u_ind(1)) ...
            '%" and scan_idx > ' num2str(key1.scan_idx -3) ...
            ' and scan_idx < ' num2str(key1.scan_idx + 3) ...
            ' and aim = "Stack"' ...
            ]),'file_name');
    end
    
    if isempty(volumename)
        display('No volume, skipping...')
        return
    end
    volumename = volumename{1};
else
    volumename = name;
end

% select an earlier nearby directory and load the volume
dirs = dir(['M:\Mouse\'  volumename(1:10) '*']);
dif = bsxfun(@minus,datenum(vertcat(dirs.name),'yyyy-mm-dd_HH-MM-SS'), datenum(volumename(1:19),'yyyy-mm-dd_HH-MM-SS'));
dirs = dirs(dif<0);
[~,idx] = max(dif(dif<0));
volumename = ['M:\Mouse\' dirs(idx).name '\AODAcq\' volumename];
[x, y, z] = fetchn(MaskCells(key1),'img_x','img_y','img_z');
points = [x, y, z];
fn = aodReader(volumename,'Volume','ch1');
aod_step_size = (fn.z(end) - fn.z(1))/length(fn.z);

% convert points to index
pointi = nan(size(points));
for icell = 1:size(points,1)
    [~,pointi(icell,1)] = min(abs(points(icell,1)-fn.x));
    [~,pointi(icell,2)] = min(abs(points(icell,2)- fn.y));
    [~,pointi(icell,3)] = min(abs(points(icell,3)-fn.z));
end

data1 = normalize(fn(:,:,:,1));
data1 = repmat(reshape(data1,size(data1,1),size(data1,2),1,size(data1,3)),[1 1 3 1]);

%% MPScan
if nargin<3
    key2 = [];
    key2.exp_date = key1.exp_date;
    [x, y, z] = fetch1(Scans(key1),'x','y','z');
    ks = fetch(Scans(key2,['scan_idx<' num2str(key1.scan_idx) ...
        ' and scan_prog <> "AOD" and aim = "stack"'...
        ' and x <' num2str(x+24 -14 ) ' and x >' num2str(x-10 -14) ...
        ' and y <' num2str(y+38 -28 ) ' and y >' num2str(y-10 -28) ...
        ' and z <' num2str(z+10 +80 ) ' and z >' num2str(z-90 +80)]));
    scans = [ks.scan_idx];
    if isempty(scans);disp 'No MpScan stack found, skipping...'; stop = true;return;end
    [~,idx] = min(key1.scan_idx - scans);
    key2.scan_idx = scans(idx);
end

tp = tpReader(Scans(key2));
gr = read(tp,1); gr= reshape(gr,size(gr,1),size(gr,2),1,size(gr,3));
rd = read(tp,2); rd= reshape(rd,size(rd,1),size(rd,2),1,size(rd,3));
galvo_step_size = abs(tp.hdr.acq.zStepSize);
step = aod_step_size/galvo_step_size;

data2 = normalize(double(rd));
data2(:,:,2,:) = normalize(double(gr));
data2(:,:,3,:) = zeros(size(gr));

data2 = data2(end:-1:1,end:-1:1,:,:);

%% Plot

h = figure('NumberTitle','off',...
    'Name','Find the patched cell',...
    'KeyPressFcn',@dispkeyevent,...
    'WindowButtonDownFcn',@cellInput,...
    'WindowScrollWheelFcn', @doScroll);

subplot(121);
if size(data1,4)<ind;ind = size(data1,4);end
image(normalize(data1(:,:,:,ind)))
axis image
hold on

celli = find(pointi(:,3)==ind);
for icell = 1:length(celli)
    text(pointi(celli(icell),2),pointi(celli(icell),1),'+',...
        'HorizontalAlignment','center','VerticalAlignment','middle')
    text(pointi(celli(icell),2),pointi(celli(icell),1),num2str(celli(icell)),...
        'VerticalAlignment','top')
end

subplot(122)
image(normalize(data2(:,:,:,ind)))
axis image

end

function dispkeyevent(~, event)
global ind
global offset
global data1
global data2
global pointi
global markId
global xLoc
global yLoc
global step
global stop 

% step = size(data1,4)/size(data2,4);
if strcmp(event.Key,'uparrow')
    if ind<size(data2,4)
        ind = ind+1;
    end
elseif strcmp(event.Key,'downarrow')
    if ind>1
        ind = ind-1;
    end
elseif strcmp(event.Key,'leftarrow')
    offset = offset + 1;
elseif strcmp(event.Key,'rightarrow')
    offset = offset - 1;
elseif strcmp(event.Key,'pageup')
    if ind<size(data2,4)
        ind = ind+1;
    end
    offset = offset - 1;
elseif strcmp(event.Key,'pagedown')
    if ind>1
        ind = ind-1;
    end
    offset = offset + 1;
elseif strcmp(event.Key,'insert')
    [xLoc, yLoc] = ginput(1);
    if  sign(xLoc)>0 && sign(yLoc)>0
        ifr = max(1,min(size(data1,4),round(step\(ind+offset))));
        [~,markId(end+1)] = min(pdist2([yLoc xLoc ifr],pointi));
    end
elseif strcmp(event.Key,'space')
    offset = -24;
elseif strcmp(event.Key,'return')
    stop = true;
    close all
    return
elseif strcmp(event.Key,'escape')
    disp 'Quiting ...'
    markId = [];
    stop = true;
    close all
    return
else
    display(event.Key)
end

clf
s = subplot(121);
ifr = max(1,min(size(data1,4),round(step\(ind+offset))));
image(normalize(data1(:,:,:,ifr)))
axis image
axis off
hold on

celli = find(pointi(:,3)==ifr);
colors = ones(size(pointi,1),3);
colors(markId,:) = repmat([1 0 0],length(markId),1);
color = colors(celli,:);
for icell = 1:length(celli)
    text(pointi(celli(icell),2),pointi(celli(icell),1),'+',...
        'HorizontalAlignment','center','VerticalAlignment','middle','color',color(icell,:))
    text(pointi(celli(icell),2),pointi(celli(icell),1),num2str(celli(icell)),...
        'VerticalAlignment','top','color',color(icell,:))
end

subplot(122)
image(normalize(data2(:,:,:,ind)))
axis image
axis off

end

function doScroll(~,e)

global ind
global offset
global data1
global data2
global pointi
global markId
global step

subplot(121)
C1 = get (gca, 'CurrentPoint');
subplot(122)
C2 = get (gca, 'CurrentPoint');
ifr = max(1,min(size(data1,4),round(step\(ind+offset))));

if C1(1,1)>0 && C1(1,1)<size(data1,1) && C1(1,2)>0 && C1(1,2)<size(data1,2)
    if  ifr<size(data1,4) && e.VerticalScrollCount>0
        offset = offset + 1;
    elseif ifr>1 &&  e.VerticalScrollCount<0
        offset = offset - 1;
    end    
elseif C2(1,1)>0 && C2(1,1)<size(data2,1) && C2(1,2)>0 && C2(1,2)<size(data2,2)
    if ind<size(data2,4) && e.VerticalScrollCount>0
        ind = ind+1;
        offset = offset - 1;
    elseif  ind>1 && e.VerticalScrollCount<0
        ind = ind-1;
        offset = offset + 1;
    end
else
    if ind<size(data2,4) && e.VerticalScrollCount>0
        ind = ind+1;
    elseif  ind>1 && e.VerticalScrollCount<0
        ind = ind-1;
    end
end


clf
s = subplot(121);
ifr = max(1,min(size(data1,4),round(step\(ind+offset))));
image(normalize(data1(:,:,:,ifr)))
axis image
axis off
hold on

celli = find(pointi(:,3)==ifr);
colors = ones(size(pointi,1),3);
colors(markId,:) = repmat([1 0 0],length(markId),1);
color = colors(celli,:);
for icell = 1:length(celli)
    text(pointi(celli(icell),2),pointi(celli(icell),1),'+',...
        'HorizontalAlignment','center','VerticalAlignment','middle','color',color(icell,:))
    text(pointi(celli(icell),2),pointi(celli(icell),1),num2str(celli(icell)),...
        'VerticalAlignment','top','color',color(icell,:))
end

subplot(122)
image(normalize(data2(:,:,:,ind)))
axis image
axis off

end

function cellInput ( ~ , ~ )
global ind
global offset
global data1
global data2
global pointi
global markId
global xLoc
global yLoc
global step

coordinates = get (gca, 'CurrentPoint');
xLoc = coordinates(1,1);
yLoc = coordinates(1,2);
   

if  sign(xLoc)>0 && sign(yLoc)>0
     ifr = max(1,min(size(data1,4),round(step\(ind+offset))));
    if strcmp('alt',get(gcf,'Selectiontype'))
        [~,rmId] = min(pdist2([yLoc xLoc ifr],pointi));
        markId(markId==rmId) = [];
    else
        [~,markId(end+1)] = min(pdist2([yLoc xLoc ifr],pointi));
    end
end
    
clf
subplot(121)
ifr = max(1,min(size(data1,4),round(step\(ind+offset))));
image(normalize(data1(:,:,:,ifr)))
axis image
axis off
hold on
celli = find(pointi(:,3)==ifr);
colors = ones(size(pointi,1),3);
colors(markId,:) = repmat([1 0 0],length(markId),1);
color = colors(celli,:);
for icell = 1:length(celli)
    text(pointi(celli(icell),2),pointi(celli(icell),1),'+',...
        'HorizontalAlignment','center','VerticalAlignment','middle','color',color(icell,:))
    text(pointi(celli(icell),2),pointi(celli(icell),1),num2str(celli(icell)),...
        'VerticalAlignment','top','color',color(icell,:))
end

subplot(122)
image(normalize(data2(:,:,:,ind)))
axis image
axis off

end