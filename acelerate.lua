local unpack = unpack or table.unpack

local _M = {}
local min_object = 5
local ddd = {}

local function sign(value)
    if value < 0 then 
		return -1
    elseif value > 0 then 
		return 1
    else 
		return 0 
	end
end

local function compute_implicit_line_winding_number(ymin, ymax, a, b, c, s, x, y)
	if  y >= ymin and y <= ymax and a*x + b*y + c < 0 then
		return 1
	else
		return 0
	end
end

local function compute_implicit_line_nz(x1, y1, x2, y2)
	local a = y2 - y1
	local b = x1 - x2
	local c = -a*x1 - b*y1
	local s = sign(a)	
	local ymin, ymax = math.min (y1, y2), math.max (y1, y2)
	local nz = 1

	if ymin ~= y1 then
		nz = -1
	end

	if ymin == ymax then
		nz = 0
	end

	return ymin, ymax, s*a, s*b, s*c, s, nz
end

local function preparate_data(scene_objects) 
	for i = 1, #scene_objects do
		local data = scene_objects[i].data
		if data ~= nil and #data > 0 then
			local xmin = data[1].xmin
			local xmax = data[1].xmax
			local ymin = data[1].ymin
			local ymax = data[1].ymax

			for j = 1, #data do
				xmin = math.min(xmin, data[j].xmin)
				xmax = math.max(xmax, data[j].xmax)
				ymin = math.min(ymin, data[j].ymin)
				ymax = math.max(ymax, data[j].ymax)
			end
		
				scene_objects[i].xmin = xmin
				scene_objects[i].xmax = xmax
				scene_objects[i].ymin = ymin
				scene_objects[i].ymax = ymax		
			end
		end
	return scene_objects
end

local function compute_wrap(scene_objects)
	
	local xmin = scene_objects[1].xmin
	local xmax = scene_objects[1].xmax
	local ymin = scene_objects[1].ymin
	local ymax = scene_objects[1].ymax
	
	for i = 1, #scene_objects do
		xmin = math.min(xmin, scene_objects[i].xmin)
		xmax = math.max(xmax, scene_objects[i].xmax)
		ymin = math.min(ymin, scene_objects[i].ymin)
		ymax = math.max(ymax, scene_objects[i].ymax)
	end
		
	return xmin, xmax, ymin, ymax
end

----------------------------------------------------------
-- Approximate the median with the coordinates of the Cartesian axis

-- @param data : Val of the median

-- @return Approximate median
----------------------------------------------------------
local function aproximate_median(val)	
	local val_f = math.floor(val)
	if val - val_f <= 0.5 then 
		return val_f
	else
		return math.ceil(val)
	end
end



-----------------------------------------------------------

function countingSort(array)
    local min, max = aproximate_median(math.min(unpack(array))), aproximate_median(math.max(unpack(array)))
    local count = {}
    for i = min, max do
        count[i] = 0
    end

    for i = 1, #array do
        count[aproximate_median(array[i])] = count[aproximate_median(array[i])] + 1
    end

    local z = 1
    for i = min, max do
        while count[i] > 0 do
            array[z] = i
            z = z + 1
            count[i] = count[i] - 1
        end
    end

end

local function compute_median_x(data, n)
	local median = 0	
	local array = {}

	for i = 1, #data do
		local data_aux = data[i]
		for j = 1, #data_aux.data do 			
			table.insert(array, data_aux.xmin)
		end
	end
	
	countingSort(array)

	local n = #array

	if n % 2 == 0 then
		n = math.floor(n/2 + 1)
	else
		n = math.floor(n/2)
	end
	
	return aproximate_median(array[n])
end

local function compute_median_y(data, n)
	local median = 0	
	local array = {}

	for i = 1, #data do
		local data_aux = data[i]
		for j = 1, #data_aux.data do 			
			table.insert(array, data_aux.ymin)
		end
	end

	countingSort(array)

	local n = #array

	if n % 2 == 0 then
		n = math.floor(n/2 + 1)
	else
		n = math.floor(n/2)
	end

	return aproximate_median(array[n])
end

local function compute_median(data, n)
	local median = 0
	if n % 2 == 0 then 
		median = compute_median_x(data, n) 
	else 
		median = compute_median_y(data, n) 
	end
	return median
end

local function split_median_x(data, median)
	local left = {}
	local right = {}	
	for i = 1, #data do
		if data[i].xmin < median or data[i].xmax < median then
			table.insert(left, data[i])
		end
		if median <= data[i].xmin or median < data[i].xmax then
			table.insert(right, data[i])
		end
	end
	return left, right, median
end

local function split_median_y(data, median)
	local left = {}
	local right = {}
	for i = 1, #data do
		if data[i].ymin < median or data[i].ymax < median then
			table.insert(left, data[i])
		end
		if median <= data[i].ymin or median < data[i].ymax then
			table.insert(right, data[i])
		end
	end
	return left, right, median
end

local function split(root, n)
	local left = {}
	local right = {}
	median = compute_median(root, n)
	if n % 2 == 0 then 
		left, right, median = split_median_x(root, median) 
	else 
		left, right, median = split_median_y(root, median) 
	end
	left = preparate_data(left)
	right = preparate_data(right)
	return left, right, median
end

local function transform_point(x, y, xf)
    local _x, _y, w = xf : apply(x, y, 1)
    return _x / w, _y / w
end

function compute_winding_rule_cont(datas, x, y)
	local cont = 0
	for i = 1, #datas do 
		for j = 1, #datas[i].data do
			local data = datas[i].data[j]
			if data.command == 'L' then
				if y >= data.ymax or y < data.ymin or  x > data.xmax then
					--::continue::  
				elseif x <= data.xmin then
					cont = cont + data.nz							
				else
					local ymin, ymax, a, b, c, s, nz = unpack(data.implicit_line)
					local nz = data.nz*compute_implicit_line_winding_number(ymin, ymax, a, b, c, s, x, y)
					cont = cont + nz
				end
			elseif data.command == 'Q' then		
				if y >= data.ymax or y < data.ymin or  x > data.xmax then
					--::continue::  
				elseif x <= data.xmin then
					cont = cont + data.nz
				else
					local xx, yy = transform_point(x, y, data.transformation)
					local point_diagonal = data.diagonal(xx, yy)
					if point_diagonal == -data.mid_point_diagonal then
						if point_diagonal < 0 then
							cont = cont + data.nz
						end
					else
						local eval = data.implicitization(xx, yy)										
						if eval < 0 then
							cont = cont + data.nz
						end					
					end
				end
			elseif data.command == 'R' then
				if y >= data.ymax or y < data.ymin or  x > data.xmax then
					--::continue::  
				elseif x <= data.xmin then
					cont = cont + data.nz
				else				
					local xx, yy = transform_point(x, y, data.transformation)
					local point_diagonal = data.diagonal(xx, yy)	
					if point_diagonal == -data.mid_point_diagonal then
						if point_diagonal < 0 then
							cont = cont + data.nz
						end
					else					
						local eval = data.implicitization(xx, yy)		
						if eval < 0 then
							cont = cont + data.nz
						end	
					end
				end
			elseif data.command == 'C' then	
				if y >= data.ymax or y < data.ymin or  x > data.xmax then
					--::continue::  
				elseif x <= data.xmin then
					cont = cont + data.nz
				else
					local xx, yy = transform_point(x, y, data.transformation)
					local point_diagonal = data.diagonal(xx, yy)
			
					if point_diagonal == -data.mid_point_diagonal then
						if point_diagonal < 0 then 
							cont = cont + data.nz
						end
					elseif data.inside_triangle(xx, yy) == false then
						if point_diagonal < 0 then 
							cont = cont + data.nz
						elseif data.mid_point_diagonal > 0 and point_diagonal == 0 then
							cont = cont + data.nz
						end
					else
						local eval = data.implicitization(xx, yy)									
						if eval < 0 then	
							cont = cont + data.nz
						end
					end
				end
			end	
		end
	end
	return cont
end

-- 0 Chegando
-- 1 Saindo 
local function get_location(obj)
	if obj.command == "R" then
		if obj.x0_bb < obj.x2_bb or obj.x0_bb < obj.x1_bb then
			return 1
		else
			return 0
		end
	elseif obj.command == "L" then
		if obj.x0 < obj.x1 then
			return 1
		else
			return 0
		end
	elseif obj.command == "C" then
		if obj.x0_bb < obj.x3_bb or obj.x0_bb < obj.x1_bb  or obj.x0_bb < obj.x2_bb  then
			return 1
		else
			return 0
		end
	elseif obj.command == "Q" then
		if obj.x0_bb < obj.x2_bb or obj.x0_bb < obj.x1_bb then
			return 1
		else
			return 0
		end
	end
	return -1
end

local function compute_lines(nodes)
	local data = nodes.data	
	for i = 1, #data do		
		if data[i].xmin < nodes.xmax_bb and data[i].xmax > nodes.xmax_bb then
			local data_i = data[i]
			for j = 1, #data_i.data do
				if data_i.xmin < nodes.xmax_bb and data_i.xmax > nodes.xmax_bb  then
					local obj = {}
					local ymin, ymax, a, b, c, s
					local y0, y1 = 0, 0
					local l_aux = get_location(data_i.data[j])	
					if l_aux == 0 then 
						y1 =  data_i.data[i].ymax 
						y0 = nodes.ymax_bb
						if data_i.data[j].nz ~= -1 then	
							y1 = data_i.data[i].ymin

						end
					elseif l_aux == 0 then 
						y0 =  data_i.data[i].ymax
						y1 = nodes.ymax_bb 
						if data_i.nz ~= 1 then
							y0 = data_i.data[i].ymin
						end			
					end				
					
					if y0 ~= y1 then			
						ymin, ymax, a, b, c, s, obj.nz = compute_implicit_line_nz(data_i.data[i].xmax, y0, data_i.data[i].xmax, y1)	
						obj.command = "L"
						obj.xmin, obj.xmax = data_i.data[i].xmax, data_i.data[i].xmax
						obj.x0, obj.x1 = data_i.data[i].xmax, data_i.data[i].xmax
						obj.ymin, obj.ymax = ymin, ymax
						obj.implicit_line = {ymin, ymax, a, b, c, s, obj.nz}
						table.insert(nodes.data[i].data, obj)
					end					
				end
			end		
		end
	end
	return nodes
end

local function build(root, n, median, xmin_bb, xmax_bb, ymin_bb, ymax_bb)
	local node = {}		
	node.xmin_bb, node.xmax_bb, node.ymin_bb, node.ymax_bb = xmin_bb, xmax_bb, ymin_bb, ymax_bb		
	
	if #root < 5 or n >= 15 then	--
		local datas = {}	
		node.data = root
		node.cont  = 0 
		node.left = nil
		node.right = nil
		return node
	end
	
	
	local left, right, median = split(root, n)
	node.median = median
	if n % 2 == 0 then
		if #left > 0 then node.left = build(left, n + 1, median, node.xmin_bb, median, node.ymin_bb, node.ymax_bb) else node.left = nil end
		if #right > 0 then node.right =  build(right, n + 1, median, median, node.xmax_bb, node.ymin_bb, node.ymax_bb) else node.right = nil end
	else
		if #left > 0 then node.left = build(left, n + 1, median, node.xmin_bb, node.xmax_bb, node.ymin_bb, median) else node.left = nil end
		if #right > 0 then node.right =  build(right, n + 1, median, node.xmin_bb, node.xmax_bb, median, node.ymax_bb) else node.right = nil end
	end
	return node
end

----------------------------------------------------------
-- Build Kd-Tree to speed up data paths

-- @param data : Objects path 

-- @return Grid with paths
----------------------------------------------------------
function _M.compute_grid(scene_objects)
    scene_objects = preparate_data(scene_objects)
	ddd = scene_objects
	local xmin, xmax, ymin, ymax = compute_wrap(scene_objects)
	scene_objects = build(scene_objects, 0, 0, xmin, xmax, ymin, ymax)
	return scene_objects
end

function get_cel_aux (tree, x, y, n)
	if tree.data ~= nil then
		return tree
	end	
	
	if n % 2 == 0 then	
		if tree.left ~= nil and x < tree.median then --x < tree.median then --
			return get_cel_aux(tree.left, x, y, n + 1)
		else
			return get_cel_aux(tree.right, x, y, n + 1)
		end
	else		
		if tree.left ~= nil and y < tree.median then --y < tree.median then --
			return get_cel_aux(tree.left, x, y, n + 1)
		else 
			return get_cel_aux(tree.right, x, y, n + 1) 	
		end
	end
end


function _M.get_cel(tree, x, y)
	return get_cel_aux(tree, x, y, 0)
end

return _M
