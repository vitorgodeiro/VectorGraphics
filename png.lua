local facade = require"facade"
local image = require"image"
local chronos = require"chronos"
local blue = require"blue"

local util = require"util"
local xform = require"xform"
local acelerate = require"acelerate"

local is_almost_zero = util.is_almost_zero
local is_almost_one = util.is_almost_one
local is_almost_equal = util.is_almost_equal

local unpack = unpack or table.unpack
local floor = math.floor
local pattern = 1
local _M = facade.driver()

local background = _M.solid_color(_M.color.white)

local compute_shape = {}
local compute_paint = {}
local render_paint = {}
local spread_table = {}

local eps, number_iterate = 0.00000001, 50

local function stderr(...)
    io.stderr:write(string.format(...))
end

-------------------------------------------------------------------------------------------------
--------------------------------------- FUNCTION AUXILIAR ---------------------------------------
-------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- Parser object for scale

-- @param sx, sy

-- @return 22 s      : isotropic_scale
-- @return 2, sx, sy : anisotropic_scale
-- @return 0, 0, 0   : None
----------------------------------------------------------
local function parser_scale(sx, sy)
    if (is_almost_equal(sx, sy)) then
        local avg = 0.5*(sx+sy)
        if (not is_almost_one(avg)) then
            return 22, avg
        else
			return 0, 0, 0 
		end
    else
		return 2, sx, sy
    end
end

----------------------------------------------------------
-- Parser object for rotate

-- @param c, s

-- @return 1 , angle : Rotate
-- @return 0, 0, 0   : None
----------------------------------------------------------
local function parser_rotate(c, s)
    if (not is_almost_one(c) or not is_almost_zero(s)) then
    	return 1,  math.deg(atan2(s, c))
	else
		return 0, 0, 0
	end
end

----------------------------------------------------------
-- Parser object for linear

-- @param a, b, c, d

-- @return 5 , a11, a12, a21, a22 : Linear
-- @return 0, 0, 0   : None
----------------------------------------------------------
local function parser_linear(a, b, c, d)
    if (is_almost_zero(a*b+c*d) and is_almost_one(a*d-b*c) and
        is_almost_one(a*a+c*c) and is_almost_one(b*b+d*d)) then
        return parser_rotate(a, c)
    elseif (is_almost_zero(b) and is_almost_zero(c)) then
        return parser_scale(a, d)
    else
        return 5, a, b, c, d
    end
end

----------------------------------------------------------
-- Parser object for translation

-- @param tx, ty

-- @return 3, tx, ty
-- @return 0, 0, 0   : None
----------------------------------------------------------
local function parser_translation(tx, ty)
    if (not is_almost_zero(tx) or not is_almost_zero(ty)) then
        return 3, tx, ty
	else
		return 0, 0, 0
	end
end

----------------------------------------------------------
-- Parser object for affinity

-- @param a, b, tx, c, d, ty

-- @return 4, a, b, tx, c, d, ty
-- @return 0, 0, 0   : None
----------------------------------------------------------
local function parser_affinity(a, b, tx, c, d, ty)
    if (is_almost_zero(tx) and is_almost_zero(ty)) then
        return parser_linear(a, b, c, d)
    elseif (is_almost_one(a) and is_almost_zero(b) and
		is_almost_zero(c) and is_almost_one(d)) then
		return parser_translation(tx, ty);
	else
		return 4, a, b, tx, c, d, ty
	end
end

----------------------------------------------------------
-- Parser object of type xform

-- @param xf : xform 

-- @return xform after parsing
	-- None 0
	-- rotation 1
	-- anisotropic_scale 2
	-- isotropic_scale 22
	-- Translation 3
	-- Affinity	4
	-- Linear 5
----------------------------------------------------------
local function parser_xform(xf)
    return parser_affinity(unpack(xf))
end

----------------------------------------------------------
-- Compute the backface culling for 2D Triangle

-- @param coordinates

-- @return true
-- @return false
----------------------------------------------------------
local function backface_culling(coordinates)
	x0, y0, x1, y1, x2, y2 = unpack(coordinates)
	if ((x1 - x0)*(y2 - y0) - (y1-y0)*(x2-x0)) < 0 then
		return false
	end
return true
end

----------------------------------------------------------
-- Perform alpha composition

-- @param a1 : Value1 for interpolation
-- @param a2 : Value2 for interpolation
-- @param t  : Parammeter for composition

-- @return 	A new color obtained by interpolation
----------------------------------------------------------
local function alpha_composite(a1, a2, t)
    return a1 + (1-t)*a2
end

----------------------------------------------------------
-- Performs two color interpolation

-- @param color1 : Color for interpolation
-- @param color2 : Color for interpolation
-- @param value  : Value for interpolation

-- @return 	A new color obtained by interpolation
----------------------------------------------------------
local function interpolate_colors(color1, color2, t)
    local out = {}
    for i = 1, 4 do
        out[i] = (1-t)*color1[i] + t*color2[i]
    end
    return out
end

----------------------------------------------------------
-- Applies a transformation to a point

-- @param Point(x,y) 
-- @param xf : Transformations

-- @return Point after transformation
----------------------------------------------------------
local function transform_point(x, y, xf)
    local _x, _y, w = xf : apply(x, y, 1)
    return _x / w, _y / w
end

----------------------------------------------------------
-- Compute the signal of the parameter

-- @param value : Number for compute the signal

-- @return 1  : If signal is positive
-- @return -1 : If signal is negative
-- @return 0  : Otherwise
----------------------------------------------------------
local function sign(value)
    if value < 0 then 
		return -1
    elseif value > 0 then 
		return 1
    else 
		return 0 
	end
end

----------------------------------------------------------
-- Truncate the number normalized

-- @param t : number for truncate 

-- @return n : 0 <= n <= 1
----------------------------------------------------------
local function truncate_normalized(t)
    if t < 0 or t == math.huge then 
		t = 0 
    elseif t > 1 or t == -math.huge 
		then t = 1
    end
    return t
end

----------------------------------------------------------
-- Compute the derivative roughly 

-- @param f : Function
-- @param x 

-- @return roots
----------------------------------------------------------
local function approximation_derivative (f, x)
	return (f(x + eps) - f(x))/eps
end

----------------------------------------------------------
-- Solver quadratic (a*x^2 + b*x + c == 0)

-- @param a, b, c, delta 

-- @return roots
----------------------------------------------------------
function solve_quadratic(a, b, c, delta)
    b = b*.5
    delta = delta or b*b-a*c
    if delta >= 0. then
        local d = math.sqrt(delta)
        if b > 0. then
            local e = b+d
            return 2, -c, e, e, -a
        elseif b < 0. then
            local e = -b+d
            return 2, e, a, c, e
        elseif math.abs(a) > math.abs(c) then
            return 2, d, a, -d, a
        else
            return 2, -c, d, c, d
        end
    else
        return 0
    end
end

----------------------------------------------------------
-- Compute the maximum in cubic bezier curve

-- @param p0, p1, p2 : Points

-- @return maximums
----------------------------------------------------------
local function compute_cubic_maximum(p0, p1, p2, p3)
	local a = 3*(-p0 + 3*p1 - 3*p2 + p3)   
	local b = 6*(p0 - 2*p1 + p2) 
	local c = 3*(p1 - p0)    

    local n, t1, s1, t2, s2 = solve_quadratic(a,b,c)
    local out1, out2 = 0, 0

    if n > 0 then 
		out1 = t1/s1 
	end

    if n > 1 then 
		out2 = t2/s2 
	end

    return truncate_normalized(out1), truncate_normalized(out2)
end

----------------------------------------------------------
-- Compute the maximum in rational bezier curve

-- @param p0, p1, p2 : Points

-- @return maximums
----------------------------------------------------------
local function compute_rational_maximum(p0, p1, p2, w)
    local a = 2*(-1 + w)*(p0 - p2)
    local b = 2*(p0 - 2*w*p0 + 2*p1 - p2)
    local c = 2*(w*p0 - p1)

    n, r1, s1, r2, s2 = solve_quadratic(a, b, c)

    local out1, out2 = 0, 0
    if n > 0 then 
		out1 = r1/s1 
	end

    if n > 1 then 
		out2 = r2/s2 
	end

    return truncate_normalized(out1), truncate_normalized(out2)
end

----------------------------------------------------------
-- Cut cubic segment auxiliar

-- @param t0, t1, x0, y0, x1, y1, x2, y2, x3, y3

-- @return New points
----------------------------------------------------------
local function cut_cubic_segment_aux(t0, t1, x0, x1, x2, x3)
    local a = -(-1 + t0)^3*x0 + t0*(3*(-1 + t0)^2*x1 + t0*(3*x2 - 3*t0*x2 + t0*x3)) 
    local b = -(-1 + t0)^2*(-1 + t1)*x0 + t1*x1 + 2*t0*(x1 - 2*t1*x1 + t1*x2) + t0^2*(-2*x1 + 3*t1*x1 + x2 - 3*t1*x2 + t1*x3) 
    local c = -(-1 + t0)*(-1 + t1)^2*x0 + t1*(-2*(-1 + t1)*x1 + t1*x2) + t0*((1 - 4*t1 + 3*t1^2)*x1 + t1*(2*x2 - 3*t1*x2 + t1*x3)) 
    local d = -(-1 + t1)^3*x0 + t1*(3*(-1 + t1)^2*x1 + t1*(3*x2 - 3*t1*x2 + t1*x3)) 
    return a, b, c, d
end

----------------------------------------------------------
-- Cut rational quadratic segment auxiliar2

-- @param t0, t1, x0, y0, x1, y1, w1, x2, y2

-- @return New points
----------------------------------------------------------
local function cut_rational_quadratic_segment_aux2(t0, t1, x0, y0, w0, x1, y1, w1, x2, y2, w2)
    local u0 = (-1 + t0)^2*x0 + t0*(-2 *(-1 + t0)*x1 + t0*x2) 
    local v0 = (-1 + t0)^2*y0 + t0*(-2 *(-1 + t0)*y1 + t0*y2) 
    local r0 = (-1 + t0)^2*w0 + t0*(-2 *(-1 + t0)*w1 + t0*w2) 
    local u1 = (-1 + t0)*(-1 + t1)*x0 + t1*x1 + t0*(x1 - 2*t1*x1 + t1*x2) 
    local v1 = (-1 + t0)*(-1 + t1)*y0 + t1*y1 + t0*(y1 - 2*t1*y1 + t1*y2) 
    local r1 = (-1 + t0)*(-1 + t1)*w0 + t1*w1 + t0*(w1 - 2*t1*w1 + t1*w2) 
    local u2 = (-1 + t1)^2*x0 + t1*(-2*(-1 + t1)*x1 + t1*x2) 
    local v2 = (-1 + t1)^2*y0 + t1*(-2*(-1 + t1)*y1 + t1*y2) 
    local r2 = (-1 + t1)^2*w0 + t1*(-2*(-1 + t1)*w1 + t1*w2) 
    return u0, v0, r0, u1, v1, r1, u2, v2, r2
end

----------------------------------------------------------
-- Cut rational quadratic segment auxiliar

-- @param u0, v0, r0, u1, v1, r1, u2, v2, r2

-- @return New points
----------------------------------------------------------
local function cut_rational_quadratic_segment_aux(u0, v0, r0, u1, v1, r1, u2, v2, r2)
    local i0, i2 = 1./r0, 1./r2
    local i1 = math.sqrt(i0*i2)
    return u0*i0, v0*i0, u1*i1, v1*i1, r1*i1, u2*i2, v2*i2
end

----------------------------------------------------------
-- Cut rational quadratic segment

-- @param t0, t1, x0, y0, x1, y1, w1, x2, y2

-- @return New points
----------------------------------------------------------
local function cut_rational_quadratic_segment(t0, t1, x0, y0, x1, y1, w1, x2, y2)
    return cut_rational_quadratic_segment_aux(cut_rational_quadratic_segment_aux2(t0, t1, x0, y0, 1, x1, y1, w1, x2, y2, 1))
end

----------------------------------------------------------
-- Cut quadratic segment aux

-- @param t0, t1, x0, y0, x1, y1, x2, y2

-- @return New points
----------------------------------------------------------
local function cut_quadratic_segment_aux(t0, t1, x0, x1, x2)
    local u0 = (-1 + t0)^2*x0 + t0*(-2 *(-1 + t0)* x1 + t0*x2)  
    local u1 = (-1 + t0)*(-1 + t1)*x0 + t1*x1 + t0*(x1 - 2*t1*x1 + t1*x2)
    local u2 = (-1 + t1)^2*x0 + t1*(-2*(-1 + t1)*x1 + t1*x2) 
    return u0, u1, u2
end

----------------------------------------------------------
-- Cut quadratic segment

-- @param t0, t1, x0, y0, x1, y1, x2, y2

-- @return New points
----------------------------------------------------------
local function cut_quadratic_segment(t0, t1, x0, y0, x1, y1, x2, y2)
    local u0, u1, u2 = cut_quadratic_segment_aux(t0, t1, x0, x1, x2)
    local v0, v1, v2 = cut_quadratic_segment_aux(t0, t1, y0, y1, y2)
    return u0, v0, u1, v1, u2, v2
end

----------------------------------------------------------
-- Cut cubic segment

-- @param t0, t1, x0, y0, x1, y1, x2, y2, x3, y3

-- @return New points
----------------------------------------------------------
local function cut_cubic_segment(t0, t1, x0, y0, x1, y1, x2, y2, x3, y3)
    local u0, u1, u2, u3 = cut_cubic_segment_aux(t0, t1, x0, x1, x2, x3)
    local v0, v1, v2, v3 = cut_cubic_segment_aux(t0, t1, y0, y1, y2, y3)
    return u0, v0, u1, v1, u2, v2, u3, v3
end


-----------------------------------------------------------------------------------------------
--------------------------------------- TRANSFORMATIONS ---------------------------------------
-----------------------------------------------------------------------------------------------

----------------------------------------------------------
-- Compute the transformation for one object

-- @param object
-- @param xfs, a, b, c, d, e, f

-- @return The data (Points) of object after transformation
----------------------------------------------------------
function compute_transformation(object, xfs, a, b, c, d, e, f) 
	if xfs == 0 then 
		return object.data 
	elseif xfs == 1 then -- Rotate
		object.data = xform.compute_rotate_by_angle(object.data, a)
	elseif xfs == 2 then -- Scale with sx, sy
		object.data = xform.compute_anisotropic_scale(object.data, a, b)
	elseif xfs == 22 then -- Scale with s
		object.data = xform.compute_isotropic_scale(object.data, a)
	elseif xfs == 3 then -- Translatation
		object.data = xform.compute_translation(object.data, a, b)		
	elseif xfs == 4 then -- affinity
		object.data = xform.compute_affinity(object.data, a, b, c, d, e, f)
	elseif xfs == 5 then -- Linear
		object.data = xform.compute_linear(object.data, a, b, c, d)
	end	
	
	return object.data
end

----------------------------------------------------------
-- Compute the matrix of transformation 

-- @param xfs, a, b, c, d, e, f

-- @return Matrix of transformation
----------------------------------------------------------
function compute_matrix_transformation(xfs, a, b, c, d, e, f)
	if xfs == 4 then
		return xform.compute_matrix_affinity(a, b, c, d, e, f)
	elseif xfs == 5 then
		return xform.compute_matrix_linear(a, b, c, d)
	elseif xfs == 3 then
		return xform.compute_matrix_translation(a, b)
	elseif xfs == 2 then
		return xform.compute_matrix_anisotropic_scale(a, b)			
	elseif xfs == 22 then
		return xform.compute_matrix_isotropic_scale(a)
	elseif xfs == 1 then
		return xform.compute_matrix_rotate(a)
	end

	return xform.identity
end

----------------------------------------------------------
-- Compute the transformation for many objects

-- @param scene_objects : Table of objects from scene
-- @param xfs, a, b, c, d, e, f

-- @return Table of objects after transformation
----------------------------------------------------------
function compute_transformations(scene_objects, xfs, a, b, c, d, e, f) 
	if xfs == 0 then return scene_objects end
	for i=1, #scene_objects, 1 do
		
		if scene_objects[i].paint.transformation ~= nil then
			scene_objects[i].paint.transformation = scene_objects[i].paint.transformation*(compute_matrix_transformation(xfs, a, b, c, d, e, f) : inverse()	)
		end

		if _M.shape_type.path == scene_objects[i].type then
			for j = 1, #scene_objects[i].data do 
				scene_objects[i].data[j].data = compute_transformation(scene_objects[i].data[j], xfs, a, b, c, d, e, f)
			end
		end
	end	
	return scene_objects
end

--------------------------------------------------------------------------------------------------
--------------------------------------- SHAPE INTERSECTION ---------------------------------------
--------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- Compute the intersection with tanget

-- @param P0 (x0,y0), P1 (x1,y1), P2 (x2,y2), P3 (x3,y3), diagonal
--
-- @return P(x,y) with intersect
----------------------------------------------------------
local function compute_tangent_intersection(x0, y0, x1, y1, x2, y2, x3, y3, diagonal)
    if x0 > x3 then
        x0, y0, x3, y3 = x3, y3, x0, y0
        x1, y1, x2, y2 = x2, y2, x1, y1
    end

    local outx, outy
    if x1 == x2 and y1 == y2 then
        return u1, v1
    elseif x0 == x1 and y0 == y1 then
        --REMOVE local diag = diagonal(u2,v2)
        outx = x2
        outy = y2
    elseif x2 == x3 and y2 == y3 then
        --REMOVE local diag = diagonal(u1,v1)
        outx = x1
        outy = y1
    else
        outx = (x0*(x3*(-y1 + y2) + x2*(y1 - y3)) + x1*(x3*(y0 - y2) + x2*(-y0 + y3)))
        outx = outx / (-(x2 - x3)*(y0 - y1) + (x0 - x1)*(y2 - y3))

        outy = (x3*(y0 - y1)*y2 + x0*y1*y2 - x2*y0*y3 - x0*y1*y3 + x2*y1*y3 + x1*y0*(-y2 + y3))
        outy = outy / (-(x2 - x3)*(y0 - y1) + (x0 - x1)*(y2 - y3))
    end

    return outx, outy
end

----------------------------------------------------------
-- Compute the implicit equation for a line using
-- ax + by + c == 0 where a = y2-y1, b = x1-x2
-- and  c = -ax1 -by1

-- @param P1 (x1,y1)
-- @param P2 (x2, y2)
--
-- @return ymin : Lowest Y received as a parameter
-- @return ymax : Highest Y received as a parameter
-- @return sa   : a(sign of y2-y1)
-- @return sb   : b(sign of y2-y1)
-- @return sc   : c(sign of y2-y1)
-- @return s    : Sign of y2-y1 
----------------------------------------------------------
local function compute_implicit_line(x1, y1, x2, y2)
	local a = y2 - y1
	local b = x1 - x2
	local c = -a*x1 - b*y1
	local s = sign(a)	
			
	return s*a, s*b, s*c
end

----------------------------------------------------------
-- Compute the implicit equation for a line using
-- ax + by + c == 0 where a = y2-y1, b = x1-x2
-- and  c = -ax1 -by1. Plus compute non-zero 
-- winding rule

-- @param P1 (x1,y1)
-- @param P2 (x2, y2)
--
-- @return ymin : Lowest Y received as a parameter
-- @return ymax : Highest Y received as a parameter
-- @return sa   : a(sign of y2-y1)
-- @return sb   : b(sign of y2-y1)
-- @return sc   : c(sign of y2-y1)
-- @return s    : Sign of y2-y1 
-- @return nz   : Sign of non-zero winding rule
----------------------------------------------------------
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

----------------------------------------------------------
-- Compute the implicit line winding number using 
-- y > ymin && y <= ymax && ax + by + c < 0

-- @param ymin : from compute_implicit_line
-- @param ymax : from compute_implicit_line
-- @param a    : from compute_implicit_line
-- @param b    : from compute_implicit_line
-- @param c    : from compute_implicit_line
-- @param s    : from compute_implicit_line
-- @param P (x, y)

-- @return 1   : If True
-- @return 0   : If False
----------------------------------------------------------
local function compute_implicit_line_winding_number(ymin, ymax, a, b, c, s, x, y)
	if  y > ymin and y <= ymax and a*x + b*y + c < 0 then
		return 1
	else
		return 0
	end
end

----------------------------------------------------------
-- Compute if point (x,y) inside is in the path

-- @param coordinates : Coordinates of polygon
-- @param winding_rule : Rule for fill object
-- @param P (x, y)

-- @return : True if intersect
-- @return : False if not intersect
----------------------------------------------------------
function render_shape(node, cont, winding_rule, x, y)

	if x < node.xmin or y < node.ymin  then
		return false
	end

	local datas = node.data 
	for i = 1, #datas do
		local data = datas[i]
		if data.command == 'M' then 
		elseif data.command == 'L' then
			if y > data.ymax or y <= data.ymin or  x > data.xmax then
				--::continue::  
			elseif x <= data.xmin then
				cont = cont + data.nz							
			else
				local ymin, ymax, a, b, c, s, nz = unpack(data.implicit_line)
				local nz = data.nz*compute_implicit_line_winding_number(ymin, ymax, a, b, c, s, x, y)
				if nz ~= 0 then
					cont = cont + nz
				end
			end
		elseif data.command == 'Q' then					
			if y > data.ymax or y <= data.ymin or x > data.xmax then
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
			
			if y > data.ymax or y <= data.ymin or x > data.xmax then
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
			if y > data.ymax or y <= data.ymin or x > data.xmax then
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
										
					if eval > 0 then
						cont = cont + data.nz
					end
				end
			end
		end
	end
	
	if winding_rule == '0' then
		if  cont ~= 0 then
			return true
		end
	elseif winding_rule == '3' then
		if  cont % 2 == 1 then
			return true
		end
	end
	
	return false	
end
-------------------------------------------------------------------------------------
--------------------------------------- PAINT ---------------------------------------
-------------------------------------------------------------------------------------

----------------------------------------------------------
-- Compute the wrapping function clamp

-- @param t

-- @return new_value
----------------------------------------------------------
spread_table[_M.spread.clamp] = function(t)
	if t > 1 then
		return 1
	elseif t < 0 then
		return 0
	else
		return t
	end
end

----------------------------------------------------------
-- Compute the wrapping function wrap

-- @param t

-- @return new_value
----------------------------------------------------------
spread_table[_M.spread.wrap] = function(t)
	return t - math.floor(t) 
end

----------------------------------------------------------
-- Compute the wrapping function transparent

-- @param t

-- @return new_value
----------------------------------------------------------
spread_table[_M.spread.transparent] = function(t)
	if t > 1 then
		return 0
	elseif t < 0 then
		return 0
	else
		return t
	end
end

----------------------------------------------------------
-- Compute the wrapping function mirror

-- @param t

-- @return new_value
----------------------------------------------------------
spread_table[_M.spread.mirror] = function(t)
	return 2*math.abs((0.5*t - math.floor(0.5*t + 0.5)))
end

----------------------------------------------------------
-- Pre-process the data of ramp

-- @param ramp  : Data of ramps

-- @return ramp : Ramp data with preprocessed data
----------------------------------------------------------
local function get_ramp(ramp)
	local object = {}
	object.data = {}
    object.spread = ramp:get_spread()
	local stops   = ramp:get_color_stops()
    for i, s in ipairs(stops) do
		local aux = {}
        aux.offset = s:get_offset()
        aux.color = s:get_color()
		table.insert(object.data, aux)
    end
    return object
end

----------------------------------------------------------
-- Find the actual ramp for compute color

-- @param ramp  : Data of ramps
-- @param t : 0 <= t <= 1

-- @return index1 and index2
----------------------------------------------------------
local function search_ramp(ramp, t)
	if #ramp.data == 2 then
		return 1, 2
	end
  	
	local min, max = 1, #ramp.data
	local aux = true
	for i = 1, #ramp.data do
        if ramp.data[i].offset <= t then 
			min = i 
		end
		if ramp.data[i].offset >= t and aux then 
			max = i 
			aux = false
		end
    end
	return min, max
end

----------------------------------------------------------
-- Pre-process the data of solid color for one better 
-- and accelerated representation

-- @param paint  : Data of the solid color

-- @return paint : Solid color data with preprocessed data
----------------------------------------------------------
compute_paint[_M.paint_type.solid_color] = function(paint)
	local object = {}
	object.color = paint:get_solid_color()
	object.type = paint:get_type()
	return object
end

----------------------------------------------------------
-- Pre-process the data of texture

-- @param paint  : Data of the texture

-- @return paint : Texture data with preprocessed data
----------------------------------------------------------
compute_paint[_M.paint_type.texture] = function(paint)
	local object = {}
	local texture = paint:get_texture_data()
	local xfs, a, b, c, d, e, f = parser_xform(paint:get_xf())

	object.opacity = paint:get_opacity()	
	object.image = texture:get_image()
	object.spread = texture:get_spread()
	object.type = paint:get_type()
	object.width = object.image:get_width()
	object.height = object.image:get_height()
	object.transformation = compute_matrix_transformation(xfs, a, b, c, d, e, f) : inverse() 
	return object
end

----------------------------------------------------------
-- Pre-process the data of linear gradient for one better 
-- and accelerated representation

-- @param paint  : Data of the linear gradient

-- @return paint : Linear gradient data with preprocessed data
----------------------------------------------------------
compute_paint[_M.paint_type.linear_gradient] = function(paint)
	local object = {}

	object.opacity = paint:get_opacity()
	object.linear_gradient = paint:get_linear_gradient_data()
	object.ramp = get_ramp(object.linear_gradient:get_color_ramp())
	object.type = paint:get_type()

	local linear_gradient = paint:get_linear_gradient_data()
	local x1, x2 = linear_gradient:get_x1(), linear_gradient:get_x2()
	local y1, y2 = linear_gradient:get_y1(), linear_gradient:get_y2()
	local trans = xform.matrix_translation(-x1, -y1)

   	x1, y1, x2, y2 = unpack(xform.compute_translation({x1, y1, x2, y2}, -x1, -y1))
	
	local root = xform.identity
	local dist_center = math.sqrt(x2^2 + y2^2)
	
	if dist_center ~= 0 then
		local cos = x2/dist_center
		local sin = math.sqrt(1 - cos^2)
		if y2 > 0 then sin = -sin end
		local angle = math.deg(math.atan2(sin, cos))
		x1, y1, x2, y2 = unpack(xform.compute_rotate_by_angle({x1, y1, x2, y2}, angle))
		root = xform.matrix_rotate_by_angle(angle)
	end

	local xfs, a, b, c, d, e, f = parser_xform(paint:get_xf())
	object.x1, object.y1, object.x2, object.y2 = x1, y1, x2, y2
	object.length = x2 - x1
	object.transformation = root*trans*(compute_matrix_transformation(xfs, a, b, c, d, e, f) : inverse() )

	return object
end

----------------------------------------------------------
-- Pre-process the data of radial gradient for one better 
-- and accelerated representation

-- @param paint  : Data of the radial gradient

-- @return paint : Radial gradient data with preprocessed data
----------------------------------------------------------
compute_paint[_M.paint_type.radial_gradient] = function(paint)
	local object = {}
	object.opacity = paint:get_opacity()
	object.radial_gradient = paint:get_radial_gradient_data()
	object.ramp = get_ramp(object.radial_gradient:get_color_ramp())
	object.type = paint:get_type()

	local radial_gradient = paint:get_radial_gradient_data()
	local cx, cy = radial_gradient:get_cx(), radial_gradient:get_cy()
	local fx, fy = radial_gradient:get_fx(), radial_gradient:get_fy()
	local r = radial_gradient:get_r()
	local trans = xform.matrix_translation(-fx, -fy)
	cx, cy, fx, fy = unpack(xform.compute_translation({cx, cy, fx, fy}, -fx, -fy))
		
	local root = xform.identity
	local dist_center = math.sqrt(cx^2 + cy^2)
	
	if dist_center ~= 0 then
		local cos = cx/dist_center
		local sin = math.sqrt(1 - cos^2)
		if cy > 0 then sin = -sin end
		local angle = math.deg(math.atan2(sin, cos))
		cx, cy, fx, fy = unpack(xform.compute_rotate_by_angle({cx, cy, fx, fy}, angle))
		root = xform.matrix_rotate_by_angle(angle)
	end

	object.cx, object.cy, object.fx, object.fy = cx, cy, fx, fy
	object.r = r	

	local xfs, a, b, c, d, e, f = parser_xform(paint:get_xf())
	object.transformation = root*trans*(compute_matrix_transformation(xfs, a, b, c, d, e, f) : inverse() )
	
	return object
end

----------------------------------------------------------
-- Get the solid color of the object in format RGBa

-- @param paint : Object with colors in  RGBa

-- @return R, G, B, a
----------------------------------------------------------
render_paint[_M.paint_type.solid_color] = function(paint)
	return paint.color
end

render_paint[_M.paint_type.texture] = function(paint, x, y)
	local img = paint.image
	x, y = transform_point(x, y, paint.transformation)
		
	local wrapped_x = spread_table[paint.spread](x)
	local wrapped_y = spread_table[paint.spread](y)

	local tex_x = wrapped_x * paint.width
	local tex_y = wrapped_y * paint.height

	local tex_x, tex_y = math.ceil(tex_x), math.ceil(tex_y)
	local r, g, b = img:get_pixel(tex_x, tex_y, 1, 2, 3)

	 a = paint.opacity
	
	return {r, g, b, a}
end

----------------------------------------------------------
-- Get the linear gradient in format RGBa

-- @param paint  : Object with colors in  RGBa
-- @param P(x,y) : Position in space 2D(x,y)

-- @return R, G, B, a
----------------------------------------------------------
render_paint[_M.paint_type.linear_gradient] = function(paint, x, y)
	x, y = transform_point(x, y, paint.transformation)
	local ratio = (x - paint.x1)/paint.length
		
	local wrapped = spread_table[paint.ramp.spread](ratio)
	local ramp = paint.ramp
	local interpolation_coeficient = 0
	
	local cof1, cof2 = search_ramp(ramp, wrapped)

	if ramp.data[cof1].offset ~= ramp.data[cof2].offset	then
		interpolation_coeficient = (wrapped - ramp.data[cof1].offset)/(ramp.data[cof2].offset - ramp.data[cof1].offset)
	else
		interpolation_coeficient = wrapped
	end
	
	local out = interpolate_colors(ramp.data[cof1].color, ramp.data[cof2].color, interpolation_coeficient)
	out[4] = out[4]*paint.opacity

	if interpolation_coeficient == 0 and paint.ramp.spread == _M.spread.transparent then
		out[4] = 0
	end
	
	return out
end

----------------------------------------------------------
-- Get the radial gradient in format RGBa

-- @param paint  : Object with colors in  RGBa
-- @param P(x,y) : Position in space 2D(x,y)

-- @return R, G, B, a
----------------------------------------------------------
render_paint[_M.paint_type.radial_gradient] = function(paint, x, y)
	x, y = transform_point(x, y, paint.transformation)
	
	local a = x^2 + y^2
	local b = -2*(x*paint.cx + y*paint.cy)
    local c = paint.cx^2 + paint.cy^2 - paint.r^2
	local n, r1, s1, r2, s2 = solve_quadratic(a, b, c)

	local t1, t2 = 0, 0
	if n > 0 then t1 = r1/s1 end
	if n > 1 then t2 = r2/s2 end
   	local t = math.max(t1, t2)
	local ratio = 1/t
	local wrapped = spread_table[paint.ramp.spread](ratio)
	local ramp = paint.ramp
	local interpolation_coeficient = wrapped
	
	local cof1, cof2 = search_ramp(ramp, wrapped)
	
	if ramp.data[cof1].offset ~= ramp.data[cof2].offset	then
		interpolation_coeficient = (wrapped - ramp.data[cof1].offset)/(ramp.data[cof2].offset - ramp.data[cof1].offset)
	else
		interpolation_coeficient = wrapped
	end
	
	local out = interpolate_colors(ramp.data[cof1].color, ramp.data[cof2].color, interpolation_coeficient)	
	out[4] = out[4]*paint.opacity

	if interpolation_coeficient == 0 and paint.ramp.spread == _M.spread.transparent then
		out[4] = 0
	end
	
	return out
end

----------------------------------------------------------------------------------------------
--------------------------------------- GENERATE SCENE ---------------------------------------
----------------------------------------------------------------------------------------------

----------------------------------------------------------
-- Compute the point that has inflection

-- @param x0, y0, x1, y1, x2, y2, x3, y3, d2, d3, d4

-- @return P (x, y) : Point that has inflection
----------------------------------------------------------
local function compute_cubic_inflections(x0, y0, x1, y1, x2, y2, x3, y3, d2, d3, d4)
    local a, b, c = -3*d2, 3*d3, -d4

    local n, t1, s1, t2, s2 = solve_quadratic(a, b, c)
    local out1, out2 = 0, 0

    if n > 0 and s1 ~= 0 then 
		out1 = t1/s1 
	end

    if n > 1 and s2 ~= 0 then 
		out2 = t2/s2 
	end

    out1, out2 = truncate_normalized(out1), truncate_normalized(out2)

    return out1, out2
end

----------------------------------------------------------
-- Compute the point that has double point

-- @param x0, y0, x1, y1, x2, y2, x3, y3, d2, d3, d4

-- @return P (x, y) : Point that has double point
----------------------------------------------------------
local function compute_cubic_double_point(x0, y0, x1, y1, x2, y2, x3, y3, d2, d3, d4)
    local a, b, c =  d2^2, -d2*d3, d3^2 - d2*d4
    local n, t1, s1, t2, s2 = solve_quadratic(a, b, c)
    local out1, out2 = 0, 0

    if n > 0 and s1 ~= 0 then 
		out1 = t1/s1 
	end

    if n > 1 and s2 ~= 0 then 
		out2 = t2/s2
	end

    out1, out2 = truncate_normalized(out1), truncate_normalized(out2)

    return out1, out2
end

----------------------------------------------------------
-- Compute the mid point of the quadratic

-- @param t, x0, y0, x1, y1, x2, y2

-- @return P (x, y) : Mid Point of the quadratic
----------------------------------------------------------
local function at2(t, x0, y0, x1, y1, x2, y2)
    local x = (-1 + t)^2*x0 + t*(-2 *(-1 + t)*x1 + t*x2) 
    local y = (-1 + t)^2*y0 + t*(-2 *(-1 + t)*y1 + t*y2) 
    return x, y
end

----------------------------------------------------------
-- Compute the mid point of the cubic

-- @param t, x0, y0, x1, y1, x2, y2, x3, y3

-- @return P (x, y) : Mid Point of the cubic
----------------------------------------------------------
local function at3(t, x0, y0, x1, y1, x2, y2, x3, y3)
    local x = -(-1 + t)^3*x0 + t*(3*(-1 + t)^2*x1 + t*(3*x2 - 3*t*x2 + t*x3)) 
    local y = -(-1 + t)^3*y0 + t*(3*(-1 + t)^2*y1 + t*(3*y2 - 3*t*y2 + t*y3)) 
    return x, y
end

----------------------------------------------------------
-- Compute the mid point of the quadratic rational

-- @param t, x0, y0, x1, y1, w1, x2, y2

-- @return P (x, y) : Mid Point of the quadratic rational
----------------------------------------------------------
local function at2rc(t, x0, y0, x1, y1, w1, x2, y2)
    local x = (-1 + t)^2*x0 + t*(-2 *(-1 + t)*x1 + t*x2)
    local y = (-1 + t)^2*y0 + t*(-2 *(-1 + t)*y1 + t*y2)
    local w = (-1 + t)^2 + t*(-2 *(-1 + t)*w1 + t)
    return x, y, w
end

----------------------------------------------------------
-- Compute the winding rule

-- @return 0 : If Non-zero
-- @return 1 : If Zero
-- @return 2 : IF e
-- @return 3 : If even-odd
----------------------------------------------------------
local winding_rule_prefix = {
    [_M.winding_rule.non_zero] = '0',
    [_M.winding_rule.zero] = '1',
    [_M.winding_rule.even] = '2',
    [_M.winding_rule.odd] = '3'
}

----------------------------------------------------------
-- Obtain the data of circle

-- @param shape 

-- @return Data of circle
----------------------------------------------------------
compute_shape[_M.shape_type.circle] = function(shape)
    	local data = shape:get_circle_data()
        local cx, cy, r = data:get_cx(), data:get_cy(), data:get_r()
        local w = math.sqrt(2)/2

        local path = {}

        local top_left = {cx - r, cy, (cx - r)*w, (cy + r)*w, cx, cy + r}
        local top_right = {cx, cy + r, (cx + r)*w, (cy + r)*w, cx + r, cy}
        local bottom_left = {cx, cy - r, (cx - r)*w, (cy - r)*w, cx - r, cy}
        local bottom_right = {cx + r, cy, (cx + r)*w, (cy - r)*w, cx, cy - r}

        path[1] = {
                command = "M",
                data = {cx, cy}
        }
        path[2] = {
                command = "R",
                w = w,
                data = top_left
        }
        path[3] = {
                command = "R",
                w = w,
                data = top_right
        }
        path[4] = {
                command = "R",
                w = w,
                data = bottom_right
        }
        path[5] = {
                command = "R",
                w = w,
                data = bottom_left
        }

        return path
		
	--return path
end

----------------------------------------------------------
-- Obtain the data of triangle and converto to path

-- @param shape 

-- @return Data of triangle
----------------------------------------------------------
compute_shape[_M.shape_type.triangle] = function(shape)
	local data = shape:get_triangle_data()
	local x1, y1, x2, y2, x3, y3 = data:get_x1(), data:get_y1(), data:get_x2(), data:get_y2(), data:get_x3(), data:get_y3()

	local path = {}

	path[1] = {
		command = "M",
		data = {x1, y1}
	}
	
	path[2] = {
		command = "L",
		data = {x2, y2}
	}
	
	path[3] = {
		command = "L",
		data = {x3, y3}
	}
		
	return path
end

----------------------------------------------------------
-- Obtain the data of polygon and converto to path

-- @param shape 

-- @return Data of polygon
----------------------------------------------------------
compute_shape[_M.shape_type.polygon] = function(shape)
	local data = shape:get_polygon_data():get_coordinates()
	local path = {}
	
	local object = {
		command = "M",
		data = {data[1], data[2]}
	}
	table.insert(path, object)	

	for j = 3, #data , 2 do
		local x, y = data[j], data[j + 1]
		local object = {
			command = "L",
			data = {x, y}
		}
		table.insert(path, object)	
	end
	return path
end

----------------------------------------------------------
-- Get Path command and add in a table representing the Path object

-- @param command : Command (linear, degenerate, cubic ... )
-- @param start   : Position initial for get data
-- @param stop    : Position final for get data
-- @param path    : Data of the path
----------------------------------------------------------
local function add_command_path(command, start, stop, path)
	return function(self, ...)
		local table_elements = {}
		local e 

        for i = start, stop do
           	e = (select(i, ...))
			table.insert(table_elements, e)
        end		

		local object = {
			command = command,
			data = table_elements
		}
		
		if command == "Q" then
			local x0, y0, x1, y1, x2, y2 = path[#path].data[#path[#path].data -1], path[#path].data[#path[#path].data] , unpack(table_elements)
			local t = {}
			t[1], t[4] = 0, 1
			t[2] = truncate_normalized( (x0-x1)/(x0 - 2*x1 + x2) )
			t[3] = truncate_normalized( (y0-y1)/(y0 - 2*y1 + y2) )
			table.sort(t)
						
			for i = 2, 4 do
		    	if t[i-1] ~= t[i] then
					local u0, v0, u1, v1, u2, v2 = cut_quadratic_segment(t[i-1], t[i], x0, y0, x1, y1, x2, y2)
				    local object = {
						command = command,
						data = {u0, v0, u1, v1, u2, v2}
					}
					table.insert(path, object)
			        self.previous = command
		        end
			end
		elseif command == "C" then

			local x0, y0, x1, y1, x2, y2, x3, y3 = path[#path].data[#path[#path].data -1], path[#path].data[#path[#path].data] , unpack(table_elements)

			local d2 = 3*(x3*(2*y1 - y2 - y0) + x2*(2*y0 - 3*y1 + y3) + x0*(y1 - 2*y2 + y3) - x1*(y0 - 3*y2 + 2*y3))
    		local d3 = 3*((3*x2 - x3)*(y0 - y1) - x1*(2*y0 - 3*y2 + y3) + x0*(2*y1 - 3*y2 + y3))
			local d4 = 9*(x2*(y0 - y1) + x0*(y1 - y2) + x1*(y2 - y0))

			if d2 == 0 and d3 == 0 then
				if d4 ~= 0 then
					local u0, v0, u1, v1, u2, v2
					u0, v0, u2, v2 = x0, y0, x3, y3

					u1 = (x0*(x3*(-y1 + y2) + x2*(y1 - y3)) + x1*(x3*(y0 - y2) + x2*(-y0 + y3)))
		            u1 = u1 / (-(x2 - x3)*(y0 - y1) + (x0 - x1)*(y2 - y3))

		            v1 = (x3*(y0 - y1)*y2 + x0*y1*y2 - x2*y0*y3 - x0*y1*y3 + x2*y1*y3 + x1*y0*(-y2 + y3))
					v1 = v1 / (-(x2 - x3)*(y0 - y1) + (x0 - x1)*(y2 - y3))
					
					local t = {}
					t[1], t[4] = 0, 1
					t[2] = truncate_normalized((u0-u1)/(u0 - 2*u1 + u2))
					t[3] = truncate_normalized((v0-v1)/(v0 - 2*v1 + v2))
					table.sort(t)

					for i = 2, 4 do
		    			if t[i-1] ~= t[i] then
							local a, b, c, d, e, f = cut_quadratic_segment(t[i-1], t[i], u0, v0, u1, v1, u2, v2)
				    		local object = {
								command = "Q",
								data = {a, b, c, d, e, f}
							}
							table.insert(path, object)
			        		self.previous = command
						end
		        	end
					return 			
				else
					local object = {
						command = "L",
						data = {x3, y3}
					}
					
					table.insert(path, object)
			        self.previous = command
					return 
				end
			end
			
			local t = {}
		    t[1], t[10] = 0, 1
    		t[2], t[3] = compute_cubic_maximum(x0, x1, x2, x3)
		    t[4], t[5] = compute_cubic_maximum(y0, y1, y2, y3)
			t[6], t[7] = compute_cubic_inflections(x0, y0, x1, y1, x2, y2, x3, y3, d2, d3, d4)
			t[8], t[9] = compute_cubic_double_point(x0, y0, x1, y1, x2, y2, x3, y3, d2, d3, d4) 
			table.sort(t)

			for i = 2, #t do
		    	if t[i-1] ~= t[i] then
					u0, v0, u1, v1, u2, v2, u3, v3 = cut_cubic_segment(t[i-1], t[i], x0, y0, x1, y1, x2, y2, x3, y3)
					local object = {
						command = command,
						data = {u0, v0, u1, v1, u2, v2, u3, v3}
					}
					table.insert(path, object)
			        self.previous = command
				end
			end
		elseif command == "R" then
			local x0, y0, x1, y1, w, x2, y2 = path[#path].data[#path[#path].data -1], path[#path].data[#path[#path].data] , unpack(table_elements)
			t = {}
		    t[1], t[6] = 0, 1
		    t[2], t[3] = compute_rational_maximum(x0, x1, x2, w)
			t[4], t[5] = compute_rational_maximum(y0, y1, y2, w)
			table.sort(t)
	
			for i = 2, 6 do
		        if t[i-1] ~= t[i] then
           			local u0, v0, u1, v1, r, u2, v2 = cut_rational_quadratic_segment(t[i-1], t[i], x0, y0, x1, y1, w, x2, y2)
					local object = {
						command = command,
						w = r,
						data = {u0, v0, u1, v1, u2, v2}
					}
					table.insert(path, object)
		        	self.previous = command	            
		        end
			end
		end

		if command ~= "Q" and command ~= "C" and command ~= "R"  then
			table.insert(path, object)
	        self.previous = command
		end
    end
end

----------------------------------------------------------
-- Pre-process the data of path for one better and accelerated representation

-- @param path : Data of the path
----------------------------------------------------------
function make_path(path)
    return {
        previous = nil,
        begin_contour = add_command_path("M", 1, 2, path),
        linear_segment = add_command_path("L", 3, 4, path),
        degenerate_segment = add_command_path("L", 7, 8, path),
        quadratic_segment = add_command_path("Q", 3, 6, path),
        rational_quadratic_segment = add_command_path("R", 3, 7, path),
        cubic_segment = add_command_path("C", 3, 8, path),
        end_closed_contour = add_command_path("Z", 2, 1, path),
        end_open_contour = function(self) self.previous = nil end,
    }
end

----------------------------------------------------------
-- Obtain the data of path

-- @param shape 

-- @return Data of path
----------------------------------------------------------
compute_shape[_M.shape_type.path] = function(shape)
    local path = shape:get_path_data()
	local path_data = {}
	path:iterate(make_path(path_data))
	return path_data
end

----------------------------------------------------------
-- Obtain the data of rectangle

-- @param shape 

-- @return Data of rectangle
----------------------------------------------------------
compute_shape[_M.shape_type.rect] = function(shape)
	local data = shape:get_rect_data()  
	local x, y, w, h = data:get_x(), data:get_y(), data:get_width(), data:get_height()
	local path = {}

	path[1] = {
		command = "M",
		data = {x, y}
	}
	
	path[2] = {
		command = "L",
		data = {x + w, y}
	}
	
	path[3] = {
		command = "L",
		data = {x + w, y + h}
	}
	
	path[4] = {
		command = "L",
		data = {x, y + h}
	}
	
	return path
end

----------------------------------------------------------
-- Pre-process the scene in a better and accelerated representation

-- @param scene_objects : Objects that form the scene

-- @return scene: Pre-processed scene
----------------------------------------------------------
local function make_scene(scene_objects)
	local scene = { }
	local transformations = { }
	function scene.painted_element(self, winding_rule, shape, paint)
		local object = {
			type = 	_M.shape_type.path,
			shape = shape,
			data = compute_shape[shape:get_type()](shape),
			paint = compute_paint[paint:get_type()](paint),
			transformation = nil,
			winding_rule = winding_rule_prefix[winding_rule]
		}

		local xfs, a, b, c, d, e, f = parser_xform(shape:get_xf())
	
		if _M.shape_type.path == object.type then
			for i = 1, #object.data do 
				object.data[i].data = compute_transformation(object.data[i], xfs, a, b, c, d, e, f)
			end
		end

		for i = 1, #transformations do
			local xfs, a, b, c, d, e, f = parser_xform(transformations[i])

			if object.paint.transformation ~= nil then
				object.paint.transformation = object.paint.transformation*(compute_matrix_transformation(xfs, a, b, c, d, e, f) : inverse())
			end

			if _M.shape_type.path == object.type then
				for i = 1, #object.data do 
					object.data[i].data = compute_transformation(object.data[i], xfs, a, b, c, d, e, f)
				end
			end
		end
	
		table.insert(scene_objects, 1, object)
    end		

	function scene.begin_transform(self, depth, xf)
		table.insert(transformations, 1, xf)
    end

    function scene.end_transform(self, depth, xf)
        table.remove(transformations, 1)
    end
	
	return scene
end

-----------------------------------------------------------------
-- Modifies the representation of the scene in order to 
-- accelerate its computation

-- @param scene_objects : Objects from the scene

-- @return Object of the scene in a new representation that has been optimized
-----------------------------------------------------------------
local function optimize(scene_objects)
	local aux_path_z = true
	local p_x, p_y = 0, 0
	local m_x, m_y = 0, 0

	for i = 1, #scene_objects do
		local data = {}
		for j = 1, #scene_objects[i].data do
			local obj = {}		
			obj.x = {}
			obj.y = {}	
			if scene_objects[i].data[j].command == "M" then
				p_x, p_y = unpack(scene_objects[i].data[j].data)
				m_x, m_y = p_x, p_y
			elseif scene_objects[i].data[j].command == "L" then
				local ymin, ymax, a, b, c, s
				local x, y = unpack(scene_objects[i].data[j].data)
				local coordinates = {p_x, p_y, x, y}
				for k = 0, #coordinates do
					obj.x[k + 1] = coordinates[k*2 + 1]
					obj.y[k + 1] = coordinates[k*2 + 2] 				 				
				end

				ymin, ymax, a, b, c, s, obj.nz = compute_implicit_line_nz(p_x, p_y, x, y)
				obj.command = "L"
				obj.xmin, obj.xmax = math.min(p_x, x), math.max(p_x, x)
				obj.ymin, obj.ymax = ymin, ymax	
				obj.implicit_line = {ymin, ymax, a, b, c, s, obj.nz}	
				obj.x0, obj.x1 = obj.x[1], obj.x[2]
				obj.y0, obj.y1 = obj.y[1], obj.y[2]
				p_x, p_y = obj.x[2], obj.y[2]
				table.insert(data, obj)					
			elseif scene_objects[i].data[j].command == "Q" then					
				local coordinates = scene_objects[i].data[j].data
				local x0, y0, x1, y1, x2, y2 = unpack(coordinates)
				p_x, p_y = x2, y2
				obj.x0_bb, obj.x1_bb, obj.x2_bb = x0, x1, x2
				obj.y0_bb, obj.y1_bb, obj.y2_bb = y0, y1, y2	
									
				obj.command = "Q"
				obj.xmin, obj.xmax = math.min(x0, x2), math.max(x0, x2)
				obj.ymin, obj.ymax = math.min(y0, y2), math.max(y0, y2)	
				obj.nz = sign(y2 - y0)

				obj.transformation = xform.matrix_translation(-x0, -y0)					
				x0, y0, x1, y1, x2, y2 = unpack(xform.compute_translation({x0, y0, x1, y1, x2, y2}, -x0, -y0))
									
				local a, b, c = compute_implicit_line(x0, y0, x2, y2)
				
				obj.diagonal = function(x, y)
        			return sign(a*x + b*y + c)
				end

				obj.mid_point_diagonal = obj.diagonal(at2(0.5, x0, y0, x1, y1, x2, y2))
					
				local det = xform.compute_det3({x0, y0, 1, x1, y1, 1, x2, y2, 1})
					
				local da1 = 4*x1*x1*y2 - 4*x1*x2*y1
				local da2 = 4*x2*y1*y1 - 4*x1*y1*y2					
				local db1 = y1*(4*y1 - 4*y2) + y2*y2
				local db2 = x1*(4*y2-8*y1) + x2*(4*y1 - 2*y2)
				local db3 = x1*(4*x1 - 4*x2)+x2*x2
					
				if det ~= 0 then
					local imp_sign = sign(2*y2*(x1*y2 - x2*y1))
					obj.implicitization = function(x, y)
		           		local diag1 = y*da1 + x*da2
		           		local diag2 = (x^2)*db1 + y*x*db2 + (y^2)*db3
	           			local eval = diag2 - diag1
						
	           			if imp_sign < 0 then 
							eval = -eval 
						end

	           			return eval 
					end		
				else
					obj.implicitization = obj.diagonal
				end
					
				obj.x0, obj.x1, obj.x2 = x0, x1, x2
				obj.y0, obj.y1, obj.y2 = y0, y1, y2						

				table.insert(data, obj)	
			elseif scene_objects[i].data[j].command == "C" then
				local coordinates = scene_objects[i].data[j].data
				local x0, y0, x1, y1, x2, y2, x3, y3 = unpack(coordinates)
				p_x, p_y = x3, y3
				obj.x0_bb, obj.x1_bb, obj.x2_bb, obj.x3_bb = x0, x1, x2, x3
				obj.y0_bb, obj.y1_bb, obj.y2_bb, obj.y3_bb = y0, y1, y2, y3
				obj.command = "C"
				obj.xmin, obj.xmax = math.min(x0, x3), math.max(x0, x3)
				obj.ymin, obj.ymax = math.min(y0, y3), math.max(y0, y3)	

				obj.transformation = xform.matrix_translation(-x0, -y0)					
				x0, y0, x1, y1, x2, y2, x3, y3 = unpack(xform.compute_translation({x0, y0, x1, y1, x2, y2, x3, y3}, -x0, -y0))
					
				local a, b, c = compute_implicit_line(x0, y0, x3, y3)
					
				obj.diagonal = function(x, y)
        			return sign(a*x + b*y + c)
				end

				obj.mid_point_diagonal = obj.diagonal(at3(0.5, x0, y0, x1, y1, x2, y2, x3, y3))

				local inter_x, inter_y = compute_tangent_intersection(x0, y0, x1, y1, x2, y2, x3, y3, obj.diagonal)
				local triangle_det = xform.compute_det2({inter_x-x0, x3-x0, inter_y-y0, y3 - y0})

				obj.inside_triangle = function(x, y)
       				local a = xform.compute_det2({x - x0, x3 - x0, y - y0, y3 - y0})
       				local b = xform.compute_det2({inter_x - x0, x - x0, inter_y - y0, y - y0})
       				local d_sign = sign(triangle_det)
       				return d_sign * a > 0 and d_sign * b > 0 and d_sign * (a + b) < d_sign * triangle_det 
				end

				local det1 = xform.compute_det3({x0,y0,1,x1,y1,1,x2,y2,1})
   				local det2 = xform.compute_det3({x1,y1,1,x2,y2,1,x3,y3,1})

				if det1 ~= 0 or det2 ~= 0 then
					local a1 = (y1 - y2 - y3)
       				local a2 = -(4*y1^2 - 2*y1*y2 + y2^2)*x3^2
       				local a3 = (9*y2^2 - 6*y2*y3 - 4*y3^2)*x1^2
       				local a4 = (9*y1^2 - 12*y1*y3 - y3^2)*x2^2
       				local a5 = 2*x1*x3*(-y2*(6*y2 + y3) + y1*(3*y2 + 4*y3))
       				local a6 = 2*x2*(x3*(3*y1^2 - y2*y3 + y1*(-6*y2 + y3)) + x1*(y1*(9*y2 - 3*y3) - y3*(6*y2 + y3)))
					local imp_sign = sign(a1*(a2+a3+a4+a5-a6))

					local f1 = -(-9*x2*y1 + 3*x3*y1 + 9*x1*y2 - 3*x1*y3)
					local f3 = -f1
					local f6 = (9*x2*y1 - 6*x3*y1 - 9*x1*y2 + 3*x3*y2 + 6*x1*y3 - 3*x2*y3)
					local f12 = (-9*x2*y1 + 3*x3*y1 + 9*x1*y2 - 3*x1*y3)

					local f2c1 = -3*x1
					local f2c2 = 3*y1
					local f4c1 = (6*x1 - 3*x2)
					local f4c2 = (-6*y1 + 3*y2)
					local f5c1 = (-3*x1 + 3*x2 - x3)
					local f5c2 = (3*y1 - 3*y2 + y3)
					local f7c1 = (6*x1 - 3*x2)	
					local f7c2 = (-6*y1 + 3*y2)
					local f9c1 = (-3*x1 + 3*x2 - x3)
					local f9c2 = 9*x2*y1 - 9*x1*y2
					local f9c3 = (3*y1 - 3*y2 + y3)
					
					obj.implicitization = function(x, y)
          				f2 = (f2c1*y + f2c2*x)            				
        				f4 = (f4c1*y + x*f4c2)
        				f5 = (f5c1*y + x*f5c2)				            
			            f9 = (f9c1*y + f9c2 + x*f9c3)
			            f10 = (f9c1*y + x*f5c2) 
			            f11 = (f7c1*y + x*f7c2) 				        
						f7 = -(f11^2)
			            f13 = (f9c1*y + x*f9c3) 
				            
          				local eval = f1*(f2*f3 - f4*f5) + f6*(f7 + f2*f9) + f10*(f11*f12 - f13*f9)
			            eval = eval * imp_sign

			            return eval
					end
				else
					obj.implicitization = obj.diagonal
				end

				obj.x0, obj.x1, obj.x2, obj.x3 = x0, x1, x2, x3
				obj.y0, obj.y1, obj.y2, obj.y3 = y0, y1, y2, y3							
				obj.nz = sign(y3 - y0)
				table.insert(data, obj)	
			elseif scene_objects[i].data[j].command == "R" then
				aux_path_z = false--DEBUG
				local coordinates = scene_objects[i].data[j].data
				local x0, y0, x1, y1, x2, y2 = unpack(coordinates)
				obj.x0_bb, obj.x2_bb = x0, x2
				local w = scene_objects[i].data[j].w
				p_x, p_y = x2, y2
				obj.command = "R"
				obj.xmin, obj.xmax = math.min(x0, x2), math.max(x0, x2)
				obj.ymin, obj.ymax = math.min(y0, y2), math.max(y0, y2)	
				obj.nz = sign(y2 - y0)					
					
				obj.transformation = xform.matrix_translation(-x0, -y0)
				x0, y0 = transform_point(x0, y0, obj.transformation)
   				x1, y1, w = obj.transformation : apply(x1, y1, w)
				x2, y2 = transform_point(x2, y2, obj.transformation)
					
				local a, b, c = compute_implicit_line(x0, y0, x2, y2)
					
				obj.diagonal = function(x, y)
       				return sign(a*x + b*y + c)
				end

				obj.mid_point_diagonal = obj.diagonal(at2rc(0.5, x0, y0, x1, y1, w, x2, y2))
				local det = xform.compute_det3({x0, y0, 1, x1, y1, w, x2, y2, 1})
				
				local c1 = (4*x1^2 - 4*w*x1*x2 + x2^2)
				local c2 = 4*x1*x2*y1 - y2*4*x1^2
				local c3 = -4*x2*y1^2 + 4*x1*y1*y2
				local c4 = (-8*x1*y1 + 4*w*x2*y1 + 4*w*x1*y2 - 2*x2*y2)
				local c5 = (4*y1^2 - 4*w*y1*y2 + y2^2)
								
				if det ~= 0 then				
					local imp_sign = sign(2*y2*(x1*y2 - x2*y1))
					obj.implicitization = function(x, y)
						local eval = y*(c1*y + c2)
        				eval = eval + x*(c3 + y*c4 + x*c5)

        				if imp_sign < 0 then 
							eval = -eval 
						end
			            return eval
					end
				else
					obj.implicitization = obj.diagonal
				end

				obj.x0, obj.x1, obj.x2 = x0, x1, x2
				obj.y0, obj.y1, obj.y2 = y0, y1, y2
				obj.w = w					
				table.insert(data, obj)	
			elseif scene_objects[i].data[j].command == "Z" then
				aux_path_z = false
			end
		end
	
    	-- Close the path if it is not closed
		if aux_path_z and #data ~= 0 then
			local ymin, ymax, a, b, c, s
			local obj = {}		
			obj.x = {p_x, m_x}
			obj.y = {p_y, m_y}	
			obj.command = "L"
			obj.x0, obj.x1 = p_x, m_x
			obj.y0, obj.y1 = p_y, m_y
			ymin, ymax, a, b, c, s, obj.nz = compute_implicit_line_nz(p_x,  p_y, m_x, m_y)
			obj.xmin, obj.xmax = math.min(p_x, m_x), math.max(p_x, m_x)
			obj.ymin, obj.ymax = ymin, ymax
			obj.implicit_line = {ymin, ymax, a, b, c, s, obj.nz}
			table.insert(data, obj)
		end
		scene_objects[i].data = data
		scene_objects[i].type = _M.shape_type.path
	end

	return scene_objects
end

-----------------------------------------------------------------
-- Compute the color of the sample at coordinates (x,y)

-- @param accelerated : Objects to check if hit

-- @return Color at coordinate (x,y)
-----------------------------------------------------------------
local function sample_coordinate(accelerated, x, y)
	local sample
	local out = {0, 0, 0, 0}	
	local data = accelerated.data
	for i = 1, #data do		
		sample = data[i]	
		if render_shape(sample, accelerated.cont, sample.winding_rule, x, y) then 
			local temp = render_paint[sample.paint.type](sample.paint, x, y)

			for j = 1, 3 do 
				out[j] = out[j] + (1-out[4])*temp[4]*temp[j] 
			end
			out[4] = alpha_composite(out[4], temp[4], out[4])
		end	
	end

	for j = 1, 4 do
        out[j] = alpha_composite(out[j], 1, out[4])
	end
	
	for j = 1, 3 do
		if out[j] <= 0.04045 then
			out[j] = out[j]*(1./12.92)
		else
        	out[j] = ((out[j] + 0.055)/(1.055))^(2.4)
		end
	end

	return out
end

-----------------------------------------------------------------
-- Compute the color of the sample at coordinates (x,y) with 
-- supersampling

-- @param accelerated : Objects to check if hit

-- @return Color at coordinate (x,y)
-----------------------------------------------------------------
local function sample(accelerated, x, y)
	local points = blue[pattern]	
	local samples = {}

	local data = acelerate.get_cel(accelerated, x, y)	
	for i = 1, #points, 2 do
		if data == nil or #data.data == 0 then return 1, 1, 1, 1 end
		local ind = (i+1)/2
		local dx, dy = points[i], points[i + 1]
		samples[ind] = {}
		samples[ind] = sample_coordinate(data, x + dx, y + dy)
	end

	local out = {0, 0, 0, 0}
    for i = 1, #samples do
        for j = 1, 4 do
            out[j] = out[j] + samples[i][j]
        end
	end

	for j = 1, 4 do
        out[j] = out[j] / #samples
	end	
	
	for j = 1, 3 do
		if out[j] <= 0.0031308 then
			out[j] = 12.92*out[j]
		else
        	out[j] =  (1.055)*(out[j]^(1./2.4))-0.055
		end
	end

	return unpack(out)
end

local function parse(args)
	local parsed = {
		pattern = nil,
		tx = nil,
		ty = nil,
        linewidth = nil,
		maxdepth = nil,
		p = nil,
		dumptreename = nil,
		dumpcellsprefix = nil,
	}
    local options = {
        { "^(%-maxdepth:(%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "invalid option " .. all)
            parsed.maxdepth = assert(tonumber(n), "invalid option " .. all)
            assert(parsed.maxdepth >= 1, "invalid option " .. all)
            return true
        end },
        { "^(%-tx:(%-?%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            parsed.tx = assert(tonumber(n), "number invalid option " .. all)
            return true
        end },
        { "^(%-ty:(%-?%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            parsed.ty = assert(tonumber(n), "number invalid option " .. all)
            return true
        end },
        { "^%-dumptree:(.*)$", function(n)
            if not n then return false end
            parsed.dumptreename = n
            return true
        end },
        { "^%-dumpcells:(.*)$", function(n)
            if not n then return false end
            parsed.dumpcellsprefix = n
            return true
        end },
        { "^(%-p:(%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            parsed.p = assert(tonumber(n), "number invalid option " .. all)
            return true
        end },
        { "^(%-linewidth:(%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
			-- global variable
            parsed.linewidth = assert(tonumber(n),
                "number invalid option " .. all)
            return true
        end },
        { "^(%-pattern:(%d+)(.*))$", function(all, n, e)
            if not n then return false end
            assert(e == "", "trail invalid option " .. all)
            n = assert(tonumber(n), "number invalid option " .. all)
            assert(blue[n], "pattern does not exist" .. all)
            parsed.pattern = n
            return true
        end },
        { ".*", function(all)
            error("unrecognized option " .. all)
        end }
    }
    -- process options
    for i, arg in ipairs(args) do
        for j, option in ipairs(options) do
            if option[2](arg:match(option[1])) then
                break
            end
        end
    end
    return parsed
end

-----------------------------------------------------------------
-- This function should inspect the content and pre-process
-- it into a better representation, an accelerated
-- representation, to simplify the job of sample(accelerated, x, y)

-- @param content
-- @param viewport

-- @return objects for render
-----------------------------------------------------------------
function _M.accelerate(content, viewport, args)
	local parsed = parse(args)
    
    if parsed.pattern ~= nil then 
		pattern = parsed.pattern 
	end

	local scene_objects = { }
	content:get_scene_data():iterate(make_scene(scene_objects))
	scene_objects = compute_transformations(scene_objects, parser_xform(content:get_xf()))
	scene_objects = optimize(scene_objects)	
	
	local tree = acelerate.compute_grid(scene_objects)
	
    return tree --scene_objects
end

-----------------------------------------------------------------
-- Function to render scene

-- @param accelerates
-- @param viewport
-- @param file
-----------------------------------------------------------------
function _M.render(accelerated, viewport, file)
local time = chronos.chronos()
    -- Get viewport to compute pixel centers
    local vxmin, vymin, vxmax, vymax = unpack(viewport, 1, 4)
    local width, height = vxmax-vxmin, vymax-vymin
    -- Allocate output image
    local img = image.image(width, height, 4)
    -- Render
    for i = 1, height do
stderr("\r%5g%%", floor(1000*i/height)/10)
        local y = vymin+i-1.+.5
        for j = 1, width do
            local x = vxmin+j-1+.5
            img:set_pixel(j, i, sample(accelerated, x, y))
        end
    end
stderr("\n")
stderr("rendering in %.3fs\n", time:elapsed())
time:reset()
    -- Store output image
    image.png.store8(file, img)
stderr("saved in %.3fs\n", time:elapsed())
end

return _M
