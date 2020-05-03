extends Spatial

#Change this value for more complicated cubes
const cubeDimention:int = 4

onready var cube = preload("res://cube_object.tscn")

const PI2:float = PI/2
const doublePI:float = 2*PI
const RAY_LENGTH:int = 4

# [][][] of all cubes and null where missing
var cubeIx = []

var last_mouse_position:Vector2 = Vector2()

var inRotationMode:bool = false
var cameraPosition:Transform
var cameraRotationTheta:float = 0
var cameraRotationPhi:float = 0

var inManipulationMode:bool = false
var manipulationInitialized:bool = false
var manipulationObjectIx:Vector3 = Vector3()
var manipulationNormal:Vector3 = Vector3()
var manipulationRotation:float = 0.0
var manipulationAxis:Vector3 = Vector3()
var manipulationCubes:Array = []
var manipulationCubesTransform:Array = []

var postAnimationMode:bool = false

# Called when the node enters the scene tree for the first time.
func _ready():
	cameraPosition = $CameraHub.transform
	updateCamera($CameraHub)
	$main/cube_object.visible = false
	$main.translate(Vector3(-0.5,-0.5,-0.5))
	
	#generate all outher cubes of the Rubic
	var N = cubeDimention-1
	for x in range(cubeDimention):
		cubeIx.append([])
		for y in range(cubeDimention):
			cubeIx[x].append([])
			for z in range(cubeDimention):
				cubeIx[x][y].append(null)
				if x==0 or x==N or y==0 or y==N or z==0 or z==N:
					var cubeInst = cube.instance()
					cubeInst.translate(Vector3(1*x,1*y,1*z))
					cubeIx[x][y][z] = cubeInst
					$main.add_child(cubeInst)
	updateCubeNames()
	$main.scale = Vector3(1.0/cubeDimention, 1.0/cubeDimention, 1.0/cubeDimention)
	# enable draging
	set_process_unhandled_input(true)

func _unhandled_input(event):
	if postAnimationMode:
		pass
	
	if event is InputEventMouseButton:
		var mouse_pressed = event.is_pressed()

		if mouse_pressed:
			last_mouse_position = event.position
			# if no colliding proper object is found
			# then go in rotation mode
			inRotationMode = true
			
			# try to check if there is collision with known object
			var clickedObject = get_object_under_mouse($CameraHub/Camera)
			var collider = clickedObject.get("collider")
			if is_instance_valid(collider):
				var colliderName = collider.get_parent().name
				if "Shuffle" == colliderName:
					doShuffle()
					inRotationMode = false
					return
				var nameTokens = colliderName.split("_", true);
				if nameTokens.size() == 4:
					var colliderCheckName = nameTokens[0]+"_"+str(int(nameTokens[1]))+"_"+str(int(nameTokens[2]))+"_"+str(int(nameTokens[3]))
					if colliderName == colliderCheckName:
						#collect cubes for rotation
						manipulationNormal = clickedObject.normal
						#do we have a face hit
						var dotNormal = abs(manipulationNormal.dot(Vector3(1,1,1)))
						#print("dotNormal: "+str(dotNormal))
						if dotNormal > 0.9:
							inRotationMode = false
							inManipulationMode = true
							manipulationInitialized = false
							manipulationObjectIx = Vector3(int(nameTokens[1]), int(nameTokens[2]), int(nameTokens[3]))

		# when mouse is released disable modes
		else:
			if inManipulationMode:
				postAnimationMode = true
			inManipulationMode = false
			inRotationMode = false
	
	if event is InputEventMouseMotion:
		var delta = event.position - last_mouse_position
		last_mouse_position = event.position
		# in rotation mode
		if inRotationMode:
			cameraRotationPhi += -delta.x * 0.01
			cameraRotationTheta += -delta.y * 0.01
			if cameraRotationTheta > PI2:
				cameraRotationTheta = PI2
			if cameraRotationTheta < -PI2:
				cameraRotationTheta = -PI2
			updateCamera($CameraHub)

		if inManipulationMode:
			if not manipulationInitialized:
				#detect the rotation
				manipulationRotation = 0
				#detect rotation
				var normal = Vector3(0,0,0)
				if   manipulationNormal.x >  0.9: normal.x =  1
				elif manipulationNormal.x < -0.9: normal.x = -1
				elif manipulationNormal.y >  0.9: normal.y =  1
				elif manipulationNormal.y < -0.9: normal.y = -1
				elif manipulationNormal.z >  0.9: normal.z =  1
				elif manipulationNormal.z < -0.9: normal.z = -1
				
				if abs(normal.length()) < 0.9:
					inManipulationMode = false
					return
				var face_y = getQuadrant($CameraHub.rotation.y)
				#print("face_x: "+str(face_x)+ " face_y:"+str(face_y)+" normal: "+str(normal))
				var cameraHorizon
				match face_y:
					0: cameraHorizon = Vector3(1,0,0)
					1: cameraHorizon = Vector3(0,0,-1)
					2: cameraHorizon = Vector3(-1,0,0)
					3: cameraHorizon = Vector3(0,0,1)
				
				if abs(delta.x) > abs(delta.y):
					# horizontal rotation
					manipulationAxis = cameraHorizon.cross(normal)
				else:
					# vertical rotation
					manipulationAxis = cameraHorizon
				#print("face_x: "+str(face_x)+ " face_y:"+str(face_y)+" normal: "+str(normal) +" cameraHorizon: "+ str(cameraHorizon) + " manipulationAxis:"+str(manipulationAxis))				
				updateManipulationCubes(manipulationObjectIx, manipulationAxis)
				saveManipulationCubesTransformations()
				manipulationInitialized = true
			else:
				# do rotation
				manipulationRotation += (delta.y - delta.x) * 0.01
				doRotateManipulation(manipulationAxis, manipulationRotation)

var targetRotation = []
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if postAnimationMode:
		if targetRotation.size() == 0:
			#normalize rotation in 0 to 2PI
			if abs(manipulationRotation) > doublePI:
				manipulationRotation -= int(manipulationRotation/doublePI)*doublePI
			if manipulationRotation < 0:
				manipulationRotation += doublePI
			targetRotation = [roundToPI2(manipulationRotation)]
		else:
			# animate rotation to PI2 angle
			if abs(manipulationRotation - targetRotation[0]) < 0.1:
				manipulationRotation = targetRotation[0]
				doRotateManipulation(manipulationAxis, manipulationRotation)
				updateCubesAfterManipulation(manipulationObjectIx, manipulationAxis, manipulationRotation)
				clearManipulation()
				postAnimationMode = false
			else:
				if manipulationRotation < targetRotation[0]:
					manipulationRotation +=0.1
				else:
					manipulationRotation -=0.1 
				doRotateManipulation(manipulationAxis, manipulationRotation)

# rotate layer cubes
func doRotateManipulation(axis: Vector3, rotation: float):
		for i in range(manipulationCubes.size()):
			manipulationCubes[i].transform = manipulationCubesTransform[i]
			#it looks like godot does not allow duplicate names
			manipulationCubes[i].name="in process"
			rotateAround(manipulationCubes[i], axis, rotation)

func updateCubesAfterManipulation(ObjectIx: Vector3, Axis: Vector3, Rotation:float):
	# manipulationObjectIx the selected IXs
	if Axis.x <-0.9 or Axis.y <-0.9 or Axis.z <-0.9: Rotation = doublePI - Rotation
	#print("ObjectIx: "+str(ObjectIx)+" Axis: "+str(Axis)+" Rotation: "+str(Rotation))
	while Rotation > 0:
		Rotation -= PI2
		var cx = ObjectIx.x
		var cy = ObjectIx.y
		var cz = ObjectIx.z
		# rotate by 90 degrees
		var N = cubeDimention-1
		if abs(Axis.x) > 0.9:
			# rotate by X
			for j in range(cubeDimention >> 1):
				if is_instance_valid(cubeIx[cx][j][j]):
					for i in range(j,N-j):
						swap([cx,j,i],[cx,i,N-j],[cx,N-j,N-i],[cx,N-i,j])
		if abs(Axis.y) > 0.9:
			#rotate by Y
			for j in range(cubeDimention >> 1):
				if is_instance_valid(cubeIx[j][cy][j]):
					for i in range(j,N-j): 
						swap([j,cy,i],[N-i,cy,j],[N-j,cy,N-i],[i,cy,N-j])
		if abs(Axis.z) > 0.9:
			#rotate by Z
			for j in range(cubeDimention >> 1):
				if is_instance_valid(cubeIx[j][j][cz]):
					for i in range(j,N-j):
						swap([j,i,cz],[i,N-j,cz],[N-j,N-i,cz],[N-i,j,cz])
	updateCubeNames()

func swap(a:Array, b:Array, c:Array, d:Array):
	var temp = cubeIx[a[0]][a[1]][a[2]]
	cubeIx[a[0]][a[1]][a[2]] = cubeIx[b[0]][b[1]][b[2]]
	cubeIx[b[0]][b[1]][b[2]] = cubeIx[c[0]][c[1]][c[2]]
	cubeIx[c[0]][c[1]][c[2]] = cubeIx[d[0]][d[1]][d[2]]
	cubeIx[d[0]][d[1]][d[2]] = temp

func updateCubeNames():
	for x in range(cubeDimention):
		for y in range(cubeDimention):
			for z in range(cubeDimention):
				if x==0 or x==cubeDimention-1 or y==0 or y==cubeDimention-1 or z==0 or z==cubeDimention-1:
					var name = "cube_" + str(x) + "_" + str(y) + "_" + str(z)
					cubeIx[x][y][z].name = name

func saveManipulationCubesTransformations():
	#store original transformations
	manipulationCubesTransform = []
	for i in range(manipulationCubes.size()):
		manipulationCubesTransform.append(manipulationCubes[i].transform)

func clearManipulation():
	targetRotation = []
	manipulationCubes=[]
	manipulationCubesTransform=[]
	manipulationInitialized = false
	manipulationRotation = 0.0

# cast a ray from camera at mouse position, and get the object colliding with the ray
func get_object_under_mouse(camera):
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = camera.project_ray_origin(mouse_pos)
	var ray_to = ray_from + camera.project_ray_normal(mouse_pos) * RAY_LENGTH
	var space_state = get_world().direct_space_state
	var selection = space_state.intersect_ray(ray_from, ray_to)
	#print("selection: "+str(selection))
	return selection

func rotateAround(obj, axis: Vector3, angle: float):
	var tStart = Vector3(0.5,0.5,0.5)
	obj.global_translate (-tStart)
	obj.transform = obj.transform.rotated(axis, angle)
	obj.global_translate (tStart)

const PI2_values = [0, PI2, 2*PI2, 3*PI2, 4*PI2]
func roundToPI2(__rotation: float) -> float:
	#normalize rotation in 0 to 2PI
	var _rotation = __rotation
	if abs(_rotation) > doublePI:
		_rotation -= int(_rotation / doublePI) * doublePI
	if _rotation < 0:
		_rotation += doublePI
	var diffs = []
	for i in range(PI2_values.size()):
		diffs.append(abs(_rotation - PI2_values[i]))
	var min_val = diffs[0]
	_rotation = PI2_values[0]
	for i in range(1, PI2_values.size()):
		if min_val > diffs[i]:
			min_val = diffs[i]
			_rotation = PI2_values[i]
	return _rotation

func getQuadrant(angle:float) -> int:
	return int(roundToPI2(angle)/PI2)%4

func updateCamera(camera):
	camera.transform = cameraPosition
	camera.rotate_x(cameraRotationTheta)
	camera.rotate_y(cameraRotationPhi)
	#print("camera: "+ str(camera.rotation))

func updateManipulationCubes(ObjectIx: Vector3, axis: Vector3):
	var cx = ObjectIx.x
	var cy = ObjectIx.y
	var cz = ObjectIx.z
	manipulationCubes = []
	if axis.x != 0:
		#horizontal surface
		for y in range(cubeDimention):
			for z in range(cubeDimention):
				var c = cubeIx[cx][y][z]
				if is_instance_valid(c):
					manipulationCubes.append(c)
	elif axis.y != 0:
		for x in range(cubeDimention):
			for z in range(cubeDimention):
				var c = cubeIx[x][cy][z]
				if is_instance_valid(c):
					manipulationCubes.append(c)
	elif axis.z != 0:
		#vertical surface
		for x in range(cubeDimention):
			for y in range(cubeDimention):
				var c = cubeIx[x][y][cz]
				if is_instance_valid(c):
					manipulationCubes.append(c)

func doShuffle():
	randomize()
	var N = cubeDimention - 1 
	var actions = 20 + cubeDimention * randi() % 10
	for i in range(actions):
		var cx=randi() % cubeDimention
		var cy=randi() % cubeDimention
		var cz=randi() % cubeDimention
		if cx==0 or cx==N or cy==0 or cy==N: cz=N * randi() % 2
		var axis = randi() % 3
		match axis:
			0: axis = Vector3(1, 0, 0)
			1: axis = Vector3(0, 1, 0)
			2: axis = Vector3(0, 0, 1)
		var angleIx = 1 + randi() % 3
		var ObjectIx = Vector3(cx,cy,cz)
		manipulationRotation = angleIx * PI2
		updateManipulationCubes(ObjectIx, axis)
		saveManipulationCubesTransformations()
		doRotateManipulation(axis, manipulationRotation)
		updateCubesAfterManipulation(ObjectIx, axis, manipulationRotation)
