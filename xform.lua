-- Code to compute transformations

local _M = {}

local abs = math.abs
local rad = math.rad
local cos = math.cos
local sin = math.sin

local unpack = unpack or table.unpack

-- Loads transformations
local transformations = require"facade".driver() 

_M.identity = transformations.identity()

----------------------------------------------------------
-- Move Euclidean points (x, y) to Projective points (x, y, w)

-- @param x
-- @param y

-- @return P(x,y) in Projective points (x, y, w)
----------------------------------------------------------
function e2p(x, y)
	return {x, y, 1}
end

----------------------------------------------------------
-- Move Projective points (x, y, w) to Euclidean points (x, y)

-- @param x
-- @param y
-- @param w

-- @return P(x,y) in Euclidean points
----------------------------------------------------------
function p2e(x, y, w)
	return {x/w, y/w}
end

----------------------------------------------------------
-- Compute the rotation of point P(x, y) by angle

-- @param angle : Angle for rotation
-- @param x     : Position x of the rotation point
-- @param y     : Position y of the rotation point

-- @return      : Point after rotation transformation
----------------------------------------------------------
local function rotate_by_angle(angle, x, y)	
	local rotate = transformations.rotation(angle)
	local x, y, w = rotate:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the matrix of rotate

-- @param angle

-- @return   : Matrix for rotate
----------------------------------------------------------
local function matrix_rotate(angle)
	local rotate = transformations.rotation(angle)
	return rotate 
end

----------------------------------------------------------
-- Compute the rotation of point P(x, y) by cosine and sine

-- @param cos, sin
-- @param x     : Position x of the rotation point
-- @param y     : Position y of the rotation point

-- @return      : Point after rotation transformation
----------------------------------------------------------
local function rotate_by_cos_sin(cos, sin, x, y)	
	local rotate = transformations.rotation(cos, sin)
	local x, y, w = rotate:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the translation of point P(x, y)

-- @param tx : Coefficient x in translate
-- @param ty : Coefficient y in translate
-- @param x  : Position x of the rotation point
-- @param y  : Position y of the rotation point

-- @return   : Point after translation transformation
----------------------------------------------------------
local function translate(tx, ty, x, y)
	local translate = transformations.translation(tx, ty)
	local x, y, w = translate:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the matrix of translation

-- @param tx : Coefficient x in translation
-- @param ty : Coefficient y in translation

-- @return   : Matrix for translation transformation
----------------------------------------------------------
local function matrix_translation (tx, ty)
	local translate = transformations.translation(tx, ty)
	return translate
end
----------------------------------------------------------
-- Compute the anisotropic scale of point P(x, y)

-- @param sx : Coefficient x in scale
-- @param sy : Coefficient y in scale
-- @param x  : Position x of the rotation point
-- @param y  : Position y of the rotation point

-- @return   : Point after scale transformation
----------------------------------------------------------
local function anisotropic_scale(sx, sy, x, y)
	local scale = transformations.scaling(sx, sy)
	local x, y, w = scale:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the matrix of anisotropic scale 

-- @param sx : Coefficient x in scale
-- @param sy : Coefficient y in scale

-- @return   : Matrix for scale transformation
----------------------------------------------------------
local function matrix_anisotropic_scale(sx, sy)
	local scale = transformations.scaling(sx, sy)
    return scale 
end

----------------------------------------------------------
-- Compute the isotropic scale of point P(x, y)

-- @param s : Coefficient for scale
-- @param x  : Position x of the rotation point
-- @param y  : Position y of the rotation point

-- @return   : Point after scale transformation
----------------------------------------------------------
local function isotropic_scale(s, x, y)
	local scale = transformations.scaling(s)
	local x, y, w = scale:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the matrix of isotropic scale 

-- @param s : Coefficient for scale

-- @return   : Matrix for scale transformation
----------------------------------------------------------
local function matrix_isotropic_scale(s)
	local scale = transformations.scaling(s)
    return scale 
end

----------------------------------------------------------
-- Compute the affinity

-- @param a, b, tx, c, d, ty
-- @param x  : Position x of the rotation point
-- @param y  : Position y of the rotation point

-- @return   : Point after affinity transformation
----------------------------------------------------------
local function affinity(a, b, tx, c, d, ty, x, y)
	local affinity = transformations.affinity(a, b, tx, c, d, ty)
	local x, y, w = affinity:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the matrix affinity

-- @param a, b, tx, c, d, ty

-- @return   : Matrix affinity transformation
----------------------------------------------------------
local function matrix_affinity(a, b, tx, c, d, ty)
	local affinity = transformations.affinity(a, b, tx, c, d, ty)
    return affinity 
end

----------------------------------------------------------
-- Compute the linear

-- @param a11, a12, a21, a22
-- @param x  : Position x of the rotation point
-- @param y  : Position y of the rotation point

-- @return   : Point after linear transformation
----------------------------------------------------------
local function linear(a11, a12, a21, a22, x, y)
	local linear = transformations.linear(a11, a12, a21, a22)
	local x, y, w = linear:apply(x, y)
    return p2e(x, y, w)
end

----------------------------------------------------------
-- Compute the matrix linear

-- @param a11, a12, a21, a22

-- @return   : Matrix for linear transformation
----------------------------------------------------------
local function matrix_linear(a11, a12, a21, a22)
	local linear = transformations.linear(a11, a12, a21, a22)
    return linear
end

----------------------------------------------------------
-- Compute the anisotropic scale

-- @param data : Points for update values 
-- @param sx, sy   

-- @return    : Points after anisotropic scale transformation
----------------------------------------------------------
function _M.compute_anisotropic_scale(data, sx, sy)
    local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = unpack(anisotropic_scale(sx, sy, data[i], data[i+1]))
	end
    return n_data 
end

function _M.matrix_anisotropic_scale(sx, sy)
	return transformations.scaling(sx, sy)
end

----------------------------------------------------------
-- Compute the matrix anisotropic scale

-- @param sx, sy

-- @return : Matrix for anisotropic scale transformation
----------------------------------------------------------
function _M.compute_matrix_anisotropic_scale(sx, sy)
	return matrix_anisotropic_scale(sx, sy)
end

----------------------------------------------------------
-- Compute the isotropic scale

-- @param data : Points for update values 
-- @param s

-- @return     : Points after anisotropic scale transformation
----------------------------------------------------------
function _M.compute_isotropic_scale(data, s)
    local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = unpack(isotropic_scale(s,  data[i], data[i+1]))
	end
    return n_data 
end

----------------------------------------------------------
-- Compute the matrix of isotropic scale

-- @param s

-- @return : Matrix for isotropic scale transformation
----------------------------------------------------------
function _M.compute_matrix_isotropic_scale(s)
	return matrix_isotropic_scale(s)
end

----------------------------------------------------------
-- Compute the rotate by angle

-- @param data : Points for update values 
-- @param angle

-- @return     : Points after rotate transformation
----------------------------------------------------------
function _M.compute_rotate_by_angle(data, angle)
    local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = unpack(rotate_by_angle(angle, data[i], data[i+1]))
	end
    return n_data
end

function _M.compute_rotate_by_cos_sin(data, cos, sin)
    local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = (rotate_by_cos_sin(cos, sin, data[i], data[i+1]))
	end
    return n_data
end

function _M.matrix_rotate_by_angle(angle)
	return transformations.rotation(angle)
end
----
----------------------------------------------------------
-- Compute the matrix of rotate

-- @param angle

-- @return : Matrix for rotate transformation
----------------------------------------------------------
function _M.compute_matrix_rotate (angle)
	return matrix_rotate(angle)
end
----------------------------------------------------------
-- Compute the translation 

-- @param data : Points for update values 
-- @param tx, ty

-- @return     : Points after translate transformation
----------------------------------------------------------
function _M.compute_translation(data, tx, ty)
	local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = unpack(translate(tx, ty, data[i], data[i+1]))
	end
    return n_data
end

function _M.matrix_translation(tx,ty)
	return transformations.translation(tx, ty)
end
----------------------------------------------------------
-- Compute the matrix of translation

-- @param tx, ty

-- @return : Matrix for translation transformation
----------------------------------------------------------
function _M.compute_matrix_translation(tx, ty)
	return matrix_translation(tx, ty)
end

----------------------------------------------------------
-- Compute the affinity

-- @param data : Points for update values 
-- @param a, b, tx, c, d, ty

-- @return     : Points after translate transformation
----------------------------------------------------------
function _M.compute_affinity(data, a, b, tx, c, d, ty)
	local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = unpack(affinity(a, b, tx, c, d, ty, data[i], data[i+1]))
	end
    return n_data
end

----------------------------------------------------------
-- Compute the matrix affinity

-- @param a, b, tx, c, d, ty

-- @return : Matrix for affinity transformation
----------------------------------------------------------
function _M.compute_matrix_affinity(a, b, tx, c, d, ty)
	return matrix_affinity(a, b, tx, c, d, ty)
end

----------------------------------------------------------
-- Compute the linear

-- @param data : Points for update values 
-- @param a11, a12, a21, a22

-- @return     : Points after linear transformation
----------------------------------------------------------
function _M.compute_linear(data, a11, a12, a21, a22)
	local n_data = {}
	for i = 1, #data, 2 do
		n_data[i], n_data[i + 1] = unpack(linear(a11, a12, a21, a22, data[i], data[i+1]))
	end
    return n_data
end

----------------------------------------------------------
-- Compute the matrix linear

-- @param a11, a12, a21, a22

-- @return : Matrix for linear transformation
----------------------------------------------------------
function _M.compute_matrix_linear(a11, a12, a21, a22)
    return matrix_linear(a11, a12, a21, a22)
end

function _M.compute_det2(M)
	local a, b, c, d = unpack(M, 1, 4)
	return a*d - b*c
end

function _M.compute_det3(M)
	local a, b, c, d, e, f, g, h, i = unpack(M, 1, 9)
    return -c*e*g + b*f*g + c*d*h - a*f*h - b*d*i + a*e*i
end

return _M
