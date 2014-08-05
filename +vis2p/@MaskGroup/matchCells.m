function matchCells( obj )

global markId
global stop

key = fetch(obj);

close all

mouse_strain = fetch1(vis2p.Mice(key),'mouse_strain');
if strcmp(mouse_strain,'SST-Ai9'); type = 'SST';    
elseif strcmp(mouse_strain,'PV-Ai9'); type = 'PV';
elseif strcmp(mouse_strain,'VIP-Ai9'); type = 'VIP';
else type = 'red';
end

compareVolumes(vis2p.MaskGroup,key)

while ~stop
    pause(1)
end

% insert data
if ~isempty(markId)
    markId = unique(markId);
    for icell = 1:length(markId)
        key.masknum = markId(icell);
        update(vis2p.MaskTraces(key),'mask_type',type);
    end
end