-- Generado por tools/jolt/generar_cdef.py desde JoltC (Jolt Physics 5.6.0): no editar a mano.
return [[
       
enum JPC_ShapeType_ {
 JPC_SHAPE_TYPE_CONVEX,
 JPC_SHAPE_TYPE_COMPOUND,
 JPC_SHAPE_TYPE_DECORATED,
 JPC_SHAPE_TYPE_MESH,
 JPC_SHAPE_TYPE_HEIGHT_FIELD,
 JPC_SHAPE_TYPE_SOFTBODY,
 JPC_SHAPE_TYPE_USER1,
 JPC_SHAPE_TYPE_USER2,
 JPC_SHAPE_TYPE_USER3,
 JPC_SHAPE_TYPE_USER4,
};
typedef uint8_t JPC_ShapeType;
enum JPC_ShapeSubType_ {
 JPC_SHAPE_SUB_TYPE_SPHERE,
 JPC_SHAPE_SUB_TYPE_BOX,
 JPC_SHAPE_SUB_TYPE_TRIANGLE,
 JPC_SHAPE_SUB_TYPE_CAPSULE,
 JPC_SHAPE_SUB_TYPE_TAPEREDCAPSULE,
 JPC_SHAPE_SUB_TYPE_CYLINDER,
 JPC_SHAPE_SUB_TYPE_CONVEX_HULL,
 JPC_SHAPE_SUB_TYPE_STATIC_COMPOUND,
 JPC_SHAPE_SUB_TYPE_MUTABLE_COMPOUND,
 JPC_SHAPE_SUB_TYPE_ROTATED_TRANSLATED,
 JPC_SHAPE_SUB_TYPE_SCALED,
 JPC_SHAPE_SUB_TYPE_OFFSET_CENTER_OF_MASS,
 JPC_SHAPE_SUB_TYPE_MESH,
 JPC_SHAPE_SUB_TYPE_HEIGHT_FIELD,
 JPC_SHAPE_SUB_TYPE_SOFT_BODY,
 JPC_SHAPE_SUB_TYPE_USER1,
 JPC_SHAPE_SUB_TYPE_USER2,
 JPC_SHAPE_SUB_TYPE_USER3,
 JPC_SHAPE_SUB_TYPE_USER4,
 JPC_SHAPE_SUB_TYPE_USER5,
 JPC_SHAPE_SUB_TYPE_USER6,
 JPC_SHAPE_SUB_TYPE_USER7,
 JPC_SHAPE_SUB_TYPE_USER8,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX1,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX2,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX3,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX4,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX5,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX6,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX7,
 JPC_SHAPE_SUB_TYPE_USER_CONVEX8,
};
typedef uint8_t JPC_ShapeSubType;
typedef uint32_t JPC_PhysicsUpdateError;
enum JPC_ConstraintType_ {
 JPC_CONSTRAINT_TYPE_CONSTRAINT,
 JPC_CONSTRAINT_TYPE_TWO_BODY_CONSTRAINT,
};
typedef uint32_t JPC_ConstraintType;
enum JPC_ConstraintSubType_ {
 JPC_CONSTRAINT_SUB_TYPE_FIXED,
 JPC_CONSTRAINT_SUB_TYPE_POINT,
 JPC_CONSTRAINT_SUB_TYPE_HINGE,
 JPC_CONSTRAINT_SUB_TYPE_SLIDER,
 JPC_CONSTRAINT_SUB_TYPE_DISTANCE,
 JPC_CONSTRAINT_SUB_TYPE_CONE,
 JPC_CONSTRAINT_SUB_TYPE_SWING_TWIST,
 JPC_CONSTRAINT_SUB_TYPE_SIX_DOF,
 JPC_CONSTRAINT_SUB_TYPE_PATH,
 JPC_CONSTRAINT_SUB_TYPE_VEHICLE,
 JPC_CONSTRAINT_SUB_TYPE_RACK_AND_PINION,
 JPC_CONSTRAINT_SUB_TYPE_GEAR,
 JPC_CONSTRAINT_SUB_TYPE_PULLEY,
 JPC_CONSTRAINT_SUB_TYPE_USER1,
 JPC_CONSTRAINT_SUB_TYPE_USER2,
 JPC_CONSTRAINT_SUB_TYPE_USER3,
 JPC_CONSTRAINT_SUB_TYPE_USER4,
};
typedef uint32_t JPC_ConstraintSubType;
enum JPC_ConstraintSpace_ {
 JPC_CONSTRAINT_SPACE_LOCAL_TO_BODY_COM,
 JPC_CONSTRAINT_SPACE_WORLD_SPACE,
};
typedef uint32_t JPC_ConstraintSpace;
enum JPC_MotionType_ {
 JPC_MOTION_TYPE_STATIC,
 JPC_MOTION_TYPE_KINEMATIC,
 JPC_MOTION_TYPE_DYNAMIC,
};
typedef uint8_t JPC_MotionType;
enum JPC_MotionQuality_ {
 JPC_MOTION_QUALITY_DISCRETE,
 JPC_MOTION_QUALITY_LINEAR_CAST,
};
typedef uint8_t JPC_MotionQuality;
enum JPC_OverrideMassProperties_ {
 JPC_OVERRIDE_MASS_PROPS_CALC_MASS_INERTIA,
 JPC_OVERRIDE_MASS_PROPS_CALC_INERTIA,
 JPC_OVERRIDE_MASS_PROPS_MASS_INERTIA_PROVIDED,
};
typedef uint8_t JPC_OverrideMassProperties;
;
;
;
enum JPC_GroundState_ {
 JPC_CHARACTER_GROUND_STATE_ON_GROUND,
 JPC_CHARACTER_GROUND_STATE_ON_STEEP_GROUND,
 JPC_CHARACTER_GROUND_STATE_NOT_SUPPORTED,
 JPC_CHARACTER_GROUND_STATE_IN_AIR,
};
typedef uint32_t JPC_GroundState;
enum JPC_Activation_ {
 JPC_ACTIVATION_ACTIVATE = 0,
 JPC_ACTIVATION_DONT_ACTIVATE = 1,
};
typedef uint32_t JPC_Activation;
enum JPC_ValidateResult_ {
 JPC_VALIDATE_RESULT_ACCEPT_ALL_CONTACTS,
 JPC_VALIDATE_RESULT_ACCEPT_CONTACT,
 JPC_VALIDATE_RESULT_REJECT_CONTACT,
 JPC_VALIDATE_RESULT_REJECT_ALL_CONTACTS,
};
typedef uint32_t JPC_ValidateResult;
;
;
;
;
typedef uint8_t JPC_BackFaceMode;
enum JPC_BodyType_ {
 JPC_BODY_TYPE_RIGID_BODY = 0,
 JPC_BODY_TYPE_SOFT_BODY = 1,
};
typedef uint8_t JPC_BodyType;
enum JPC_AllowedDOFs_ {
 JPC_ALLOWED_DOFS_NONE = 0b000000,
 JPC_ALLOWED_DOFS_ALL = 0b111111,
 JPC_ALLOWED_DOFS_TRANSLATIONX = 0b000001,
 JPC_ALLOWED_DOFS_TRANSLATIONY = 0b000010,
 JPC_ALLOWED_DOFS_TRANSLATIONZ = 0b000100,
 JPC_ALLOWED_DOFS_ROTATIONX = 0b001000,
 JPC_ALLOWED_DOFS_ROTATIONY = 0b010000,
 JPC_ALLOWED_DOFS_ROTATIONZ = 0b100000,
 JPC_ALLOWED_DOFS_PLANE2D = JPC_ALLOWED_DOFS_TRANSLATIONX | JPC_ALLOWED_DOFS_TRANSLATIONY | JPC_ALLOWED_DOFS_ROTATIONZ,
};
typedef uint8_t JPC_AllowedDOFs;
enum JPC_Features_ {
 JPC_FEATURE_DOUBLE_PRECISION = (1 << 0),
 JPC_FEATURE_NEON = (1 << 1),
 JPC_FEATURE_SSE = (1 << 2),
 JPC_FEATURE_SSE4_1 = (1 << 3),
 JPC_FEATURE_SSE4_2 = (1 << 4),
 JPC_FEATURE_AVX = (1 << 5),
 JPC_FEATURE_AVX2 = (1 << 6),
 JPC_FEATURE_AVX512 = (1 << 7),
 JPC_FEATURE_F16C = (1 << 8),
 JPC_FEATURE_LZCNT = (1 << 9),
 JPC_FEATURE_TZCNT = (1 << 10),
 JPC_FEATURE_FMADD = (1 << 11),
 JPC_FEATURE_PLATFORM_DETERMINISTIC = (1 << 12),
 JPC_FEATURE_FLOATING_POINT_EXCEPTIONS = (1 << 13),
 JPC_FEATURE_DEBUG = (1 << 14),
};
typedef uint32_t JPC_Features;
typedef int JPC_ShapeColor;
typedef int JPC_SoftBodyConstraintColor;
;
;
;
typedef uint8_t JPC_ActiveEdgeMode;
;
;
typedef uint8_t JPC_CollectFacesMode;
;
;
typedef uint8_t JPC_SwingType;
;
;
typedef uint32_t JPC_SixDOFConstraint_Axis;
;
;
;
;
;
;
;
;
enum JPC_SpringMode_ {
 JPC_SPRING_MODE_FREQUENCY_AND_DAMPING = 0,
 JPC_SPRING_MODE_STIFFNESS_AND_DAMPING = 1,
};
typedef uint8_t JPC_SpringMode;
enum JPC_MotorState_ {
 JPC_MOTOR_STATE_OFF = 0,
 JPC_MOTOR_STATE_VELOCITY = 1,
 JPC_MOTOR_STATE_POSITION = 2,
};
typedef uint32_t JPC_MotorState;
 void JPC_RegisterDefaultAllocator();
 void JPC_FactoryInit();
 void JPC_FactoryDelete();
 void JPC_RegisterTypes();
 void JPC_UnregisterTypes();
typedef bool(*JPC_AssertFailedFunction)(const char *inExpression, const char *inMessage, const char *inFile, unsigned int inLine);
 void JPC_SetAssertFailed(JPC_AssertFailedFunction fn);
typedef struct JPC_Float3 {
 float x;
 float y;
 float z;
} JPC_Float3;
typedef struct JPC_Vec2 {
 float x;
 float y;
} JPC_Vec2;
typedef struct JPC_Vec3 {
 float x __attribute__((aligned(16)));
 float y;
 float z;
 float _w;
} JPC_Vec3;
typedef struct JPC_Vec4 {
 float x __attribute__((aligned(16)));
 float y;
 float z;
 float w;
} JPC_Vec4;
typedef struct JPC_DVec3 {
 double x __attribute__((aligned(32)));
 double y;
 double z;
 double _w;
} JPC_DVec3;
typedef struct JPC_Quat {
 float x __attribute__((aligned(16)));
 float y;
 float z;
 float w;
} JPC_Quat;
typedef struct JPC_Mat44 {
 JPC_Vec4 col[3] __attribute__((aligned(16)));
 JPC_Vec3 col3;
} JPC_Mat44;
typedef struct JPC_DMat44 {
 JPC_Vec4 col[3] __attribute__((aligned(32)));
 JPC_DVec3 col3;
} JPC_DMat44;
typedef struct JPC_Color {
 uint8_t r __attribute__((aligned(4)));
 uint8_t g;
 uint8_t b;
 uint8_t a;
} JPC_Color;
 typedef JPC_Vec3 JPC_RVec3;
 typedef JPC_Mat44 JPC_RMat44;
 typedef float Real;
typedef uint32_t JPC_BodyID;
typedef uint32_t JPC_SubShapeID;
typedef uint8_t JPC_BroadPhaseLayer;
 typedef uint16_t JPC_ObjectLayer;
typedef struct JPC_IndexedTriangleNoMaterial {
 uint32_t idx[3];
} JPC_IndexedTriangleNoMaterial;
typedef struct JPC_IndexedTriangle {
 uint32_t idx[3];
 uint32_t materialIndex;
 uint32_t userData;
} JPC_IndexedTriangle;
typedef struct JPC_RayCast {
 JPC_Vec3 Origin;
 JPC_Vec3 Direction;
} JPC_RayCast;
typedef struct JPC_RRayCast {
 JPC_RVec3 Origin;
 JPC_Vec3 Direction;
} JPC_RRayCast;
typedef struct JPC_RayCastResult {
 JPC_BodyID BodyID;
 float Fraction;
 JPC_SubShapeID SubShapeID2;
} JPC_RayCastResult;
typedef struct JPC_ShapeCastResult {
 JPC_Vec3 ContactPointOn1;
 JPC_Vec3 ContactPointOn2;
 JPC_Vec3 PenetrationAxis;
 float PenetrationDepth;
 JPC_SubShapeID SubShapeID1;
 JPC_SubShapeID SubShapeID2;
 JPC_BodyID BodyID2;
 float Fraction;
 bool IsBackFaceHit;
} JPC_ShapeCastResult;
typedef struct JPC_CollideShapeResult {
 JPC_Vec3 ContactPointOn1;
 JPC_Vec3 ContactPointOn2;
 JPC_Vec3 PenetrationAxis;
 float PenetrationDepth;
 JPC_SubShapeID SubShapeID1;
 JPC_SubShapeID SubShapeID2;
 JPC_BodyID BodyID2;
} JPC_CollideShapeResult;
typedef struct JPC_Body JPC_Body;
typedef struct JPC_VertexList JPC_VertexList;
 JPC_VertexList* JPC_VertexList_new(const JPC_Float3* storage, size_t len);
 void JPC_VertexList_delete(JPC_VertexList* object);
typedef struct JPC_IndexedTriangleList JPC_IndexedTriangleList;
 JPC_IndexedTriangleList* JPC_IndexedTriangleList_new(const JPC_IndexedTriangle* storage, size_t len);
 void JPC_IndexedTriangleList_delete(JPC_IndexedTriangleList* object);
typedef struct JPC_Shape JPC_Shape;
 uint32_t JPC_Shape_GetRefCount(const JPC_Shape* self);
 void JPC_Shape_AddRef(const JPC_Shape* self);
 void JPC_Shape_Release(const JPC_Shape* self);
 uint64_t JPC_Shape_GetUserData(const JPC_Shape* self);
 void JPC_Shape_SetUserData(JPC_Shape* self, uint64_t userData);
 JPC_ShapeType JPC_Shape_GetType(const JPC_Shape* self);
 JPC_ShapeSubType JPC_Shape_GetSubType(const JPC_Shape* self);
 uint64_t JPC_Shape_GetSubShapeUserData(const JPC_Shape* self, JPC_SubShapeID inSubShapeID);
 JPC_Vec3 JPC_Shape_GetCenterOfMass(const JPC_Shape* self);
 float JPC_Shape_GetVolume(const JPC_Shape* self);
typedef struct JPC_CompoundShape JPC_CompoundShape;
 const JPC_Shape* JPC_CompoundShape_GetSubShape_Shape(
 const JPC_CompoundShape* self,
 unsigned int inIdx);
 uint32_t JPC_CompoundShape_GetSubShapeIndexFromID(
 const JPC_CompoundShape* self,
 JPC_SubShapeID inSubShapeID,
 JPC_SubShapeID* outRemainder);
typedef struct JPC_TempAllocatorImpl JPC_TempAllocatorImpl;
 JPC_TempAllocatorImpl* JPC_TempAllocatorImpl_new(unsigned int size);
 void JPC_TempAllocatorImpl_delete(JPC_TempAllocatorImpl* object);
typedef struct JPC_JobSystem JPC_JobSystem;
typedef struct JPC_JobSystemThreadPool JPC_JobSystemThreadPool;
typedef struct JPC_JobSystemSingleThreaded JPC_JobSystemSingleThreaded;
 JPC_JobSystemThreadPool* JPC_JobSystemThreadPool_new2(
 unsigned int inMaxJobs,
 unsigned int inMaxBarriers);
 JPC_JobSystemThreadPool* JPC_JobSystemThreadPool_new3(
 unsigned int inMaxJobs,
 unsigned int inMaxBarriers,
 int inNumThreads);
 void JPC_JobSystemThreadPool_delete(JPC_JobSystemThreadPool* object);
 JPC_JobSystemSingleThreaded* JPC_JobSystemSingleThreaded_new(unsigned int inMaxJobs);
 void JPC_JobSystemSingleThreaded_delete(JPC_JobSystemSingleThreaded* object);
typedef uint32_t JPC_GroupID;
typedef uint32_t JPC_SubGroupID;
typedef struct JPC_GroupFilter JPC_GroupFilter;
typedef struct JPC_CollisionGroup {
 const JPC_GroupFilter* GroupFilter;
 JPC_GroupID GroupID;
 JPC_SubGroupID SubGroupID;
} JPC_CollisionGroup;
typedef struct JPC_GroupFilterFns {
 bool (*CanCollide)(const void *self, const JPC_CollisionGroup* inGroup1, const JPC_CollisionGroup* inGroup2);
} JPC_GroupFilterFns;
 JPC_GroupFilter* JPC_GroupFilter_new(
 const void *self,
 JPC_GroupFilterFns fns);
 void JPC_GroupFilter_delete(JPC_GroupFilter* object);
typedef struct JPC_BroadPhaseLayerInterfaceFns {
 unsigned int (*GetNumBroadPhaseLayers)(const void *self);
 JPC_BroadPhaseLayer (*GetBroadPhaseLayer)(const void *self, JPC_ObjectLayer inLayer);
} JPC_BroadPhaseLayerInterfaceFns;
typedef struct JPC_BroadPhaseLayerInterface JPC_BroadPhaseLayerInterface;
 JPC_BroadPhaseLayerInterface* JPC_BroadPhaseLayerInterface_new(
 const void *self,
 JPC_BroadPhaseLayerInterfaceFns fns);
 void JPC_BroadPhaseLayerInterface_delete(JPC_BroadPhaseLayerInterface* object);
typedef struct JPC_BroadPhaseLayerFilterFns {
 bool (*ShouldCollide)(const void *self, JPC_BroadPhaseLayer inLayer);
} JPC_BroadPhaseLayerFilterFns;
typedef struct JPC_BroadPhaseLayerFilter JPC_BroadPhaseLayerFilter;
 JPC_BroadPhaseLayerFilter* JPC_BroadPhaseLayerFilter_new(
 const void *self,
 JPC_BroadPhaseLayerFilterFns fns);
 void JPC_BroadPhaseLayerFilter_delete(JPC_BroadPhaseLayerFilter* object);
typedef struct JPC_ObjectLayerFilterFns {
 bool (*ShouldCollide)(const void *self, JPC_ObjectLayer inLayer);
} JPC_ObjectLayerFilterFns;
typedef struct JPC_ObjectLayerFilter JPC_ObjectLayerFilter;
 JPC_ObjectLayerFilter* JPC_ObjectLayerFilter_new(
 const void *self,
 JPC_ObjectLayerFilterFns fns);
 void JPC_ObjectLayerFilter_delete(JPC_ObjectLayerFilter* object);
typedef struct JPC_BodyFilterFns {
 bool (*ShouldCollide)(const void *self, JPC_BodyID inBodyID);
 bool (*ShouldCollideLocked)(const void *self, const JPC_Body *inBodyID);
} JPC_BodyFilterFns;
typedef struct JPC_BodyFilter JPC_BodyFilter;
 JPC_BodyFilter* JPC_BodyFilter_new(
 const void *self,
 JPC_BodyFilterFns fns);
 void JPC_BodyFilter_delete(JPC_BodyFilter* object);
typedef struct JPC_ShapeFilter JPC_ShapeFilter;
typedef struct JPC_ShapeFilterFns {
 bool (*ShouldCollide)(const void *self, const JPC_ShapeFilter *filter, const JPC_Shape *inShape2, JPC_SubShapeID inSubShapeIDOfShape2);
 bool (*ShouldCollideTwoShapes)(const void *self, const JPC_ShapeFilter *filter,
  const JPC_Shape *inShape1, JPC_SubShapeID inSubShapeIDOfShape1,
  const JPC_Shape *inShape2, JPC_SubShapeID inSubShapeIDOfShape2);
} JPC_ShapeFilterFns;
 JPC_ShapeFilter* JPC_ShapeFilter_new(
 const void *self,
 JPC_ShapeFilterFns fns);
 JPC_BodyID JPC_ShapeFilter_getBodyID2(const JPC_ShapeFilter* self);
 void JPC_ShapeFilter_delete(JPC_ShapeFilter* object);
typedef struct JPC_SimShapeFilterFns {
 bool (*ShouldCollide)(
  const void *self,
  const JPC_Body *inBody1, const JPC_Shape *inShape1, JPC_SubShapeID inSubShapeIDOfShape1,
  const JPC_Body *inBody2, const JPC_Shape *inShape2, JPC_SubShapeID inSubShapeIDOfShape2);
} JPC_SimShapeFilterFns;
typedef struct JPC_SimShapeFilter JPC_SimShapeFilter;
 JPC_SimShapeFilter* JPC_SimShapeFilter_new(
 const void *self,
 JPC_SimShapeFilterFns fns);
 void JPC_SimShapeFilter_delete(JPC_SimShapeFilter* object);
typedef struct JPC_ObjectVsBroadPhaseLayerFilterFns {
 bool (*ShouldCollide)(const void *self, JPC_ObjectLayer inLayer1, JPC_BroadPhaseLayer inLayer2);
} JPC_ObjectVsBroadPhaseLayerFilterFns;
typedef struct JPC_ObjectVsBroadPhaseLayerFilter JPC_ObjectVsBroadPhaseLayerFilter;
 JPC_ObjectVsBroadPhaseLayerFilter* JPC_ObjectVsBroadPhaseLayerFilter_new(
 const void *self,
 JPC_ObjectVsBroadPhaseLayerFilterFns fns);
 void JPC_ObjectVsBroadPhaseLayerFilter_delete(JPC_ObjectVsBroadPhaseLayerFilter* object);
typedef struct JPC_ObjectLayerPairFilterFns {
 bool (*ShouldCollide)(const void *self, JPC_ObjectLayer inLayer1, JPC_ObjectLayer inLayer2);
} JPC_ObjectLayerPairFilterFns;
typedef struct JPC_ObjectLayerPairFilter JPC_ObjectLayerPairFilter;
 JPC_ObjectLayerPairFilter* JPC_ObjectLayerPairFilter_new(
 const void *self,
 JPC_ObjectLayerPairFilterFns fns);
 void JPC_ObjectLayerPairFilter_delete(JPC_ObjectLayerPairFilter* object);
typedef struct JPC_ContactPoints {
 unsigned int length;
 JPC_Vec3 points[64];
} JPC_ContactPoints;
typedef struct JPC_ContactManifold {
 JPC_RVec3 BaseOffset;
 JPC_Vec3 WorldSpaceNormal;
 float PenetrationDepth;
 JPC_SubShapeID SubShapeID1;
 JPC_SubShapeID SubShapeID2;
 JPC_ContactPoints RelativeContactPointsOn1;
 JPC_ContactPoints RelativeContactPointsOn2;
} JPC_ContactManifold;
typedef struct JPC_ContactSettings {
 float CombinedFriction;
 float CombinedRestitution;
 float InvMassScale1;
 float InvInertiaScale1;
 float InvMassScale2;
 float InvInertiaScale2;
 bool IsSensor;
 JPC_Vec3 RelativeLinearSurfaceVelocity;
 JPC_Vec3 RelativeAngularSurfaceVelocity;
} JPC_ContactSettings;
typedef struct JPC_SubShapeIDPair {
 JPC_BodyID Body1ID;
 JPC_SubShapeID SubShapeID1;
 JPC_BodyID Body2ID;
 JPC_SubShapeID SubShapeID2;
} JPC_SubShapeIDPair;
typedef struct JPC_ShapeCastSettings {
 JPC_ActiveEdgeMode ActiveEdgeMode;
 JPC_CollectFacesMode CollectFacesMode;
 float CollisionTolerance;
 float PenetrationTolerance;
 JPC_Vec3 ActiveEdgeMovementDirection;
 float ExtraConvexRadius;
 JPC_BackFaceMode BackFaceModeTriangles;
 JPC_BackFaceMode BackFaceModeConvex;
 bool UseShrunkenShapeAndConvexRadius;
 bool ReturnDeepestPoint;
} JPC_ShapeCastSettings;
typedef struct JPC_CollideShapeSettings {
 JPC_ActiveEdgeMode ActiveEdgeMode;
 JPC_CollectFacesMode CollectFacesMode;
 float CollisionTolerance;
 float PenetrationTolerance;
 JPC_Vec3 ActiveEdgeMovementDirection;
 float MaxSeparationDistance;
 JPC_BackFaceMode BackFaceMode;
} JPC_CollideShapeSettings;
typedef struct JPC_ContactListenerFns {
 JPC_ValidateResult (*OnContactValidate)(
  void *self,
  const JPC_Body *inBody1,
  const JPC_Body *inBody2,
  JPC_RVec3 inBaseOffset,
  const JPC_CollideShapeResult *inCollisionResult);
 void (*OnContactAdded)(
  void *self,
  const JPC_Body *inBody1,
  const JPC_Body *inBody2,
  const JPC_ContactManifold *inManifold,
  JPC_ContactSettings *ioSettings);
 void (*OnContactPersisted)(
  void *self,
  const JPC_Body *inBody1,
  const JPC_Body *inBody2,
  const JPC_ContactManifold *inManifold,
  JPC_ContactSettings *ioSettings);
 void (*OnContactRemoved)(
  void *self,
  const JPC_SubShapeIDPair *inSubShapePair);
} JPC_ContactListenerFns;
typedef struct JPC_ContactListener JPC_ContactListener;
 JPC_ContactListener* JPC_ContactListener_new(
 void *self,
 JPC_ContactListenerFns fns);
 void JPC_ContactListener_delete(JPC_ContactListener* object);
static const unsigned int JPC_ContactPointsCapacity = 64;
typedef struct JPC_CollisionEstimationResult {
 JPC_Vec3 LinearVelocity1;
 JPC_Vec3 AngularVelocity1;
 JPC_Vec3 LinearVelocity2;
 JPC_Vec3 AngularVelocity2;
 JPC_Vec3 FrictionPoint;
 JPC_Vec3 Tangent1;
 JPC_Vec3 Tangent2;
 float FrictionImpulse1;
 float FrictionImpulse2;
 float AngularFrictionImpulse;
 unsigned int NumImpulses;
 float Impulses[JPC_ContactPointsCapacity];
} JPC_CollisionEstimationResult;
 void JPC_EstimateCollisionResponse(
 const JPC_Body* inBody1,
 const JPC_Body* inBody2,
 const JPC_ContactManifold* inManifold,
 JPC_CollisionEstimationResult* outResult,
 float inCombinedFriction,
 float inCombinedRestitution,
 float inMinVelocityForRestitution,
 unsigned int inNumIterations
);
typedef struct JPC_CastShapeCollector JPC_CastShapeCollector;
typedef struct JPC_CastShapeCollectorFns {
 void (*Reset)(void *self);
 void (*AddHit)(void *self, JPC_CastShapeCollector *base, const JPC_ShapeCastResult *Result);
} JPC_CastShapeCollectorFns;
 JPC_CastShapeCollector* JPC_CastShapeCollector_new(
 void *self,
 JPC_CastShapeCollectorFns fns);
 void JPC_CastShapeCollector_delete(JPC_CastShapeCollector* object);
 void JPC_CastShapeCollector_UpdateEarlyOutFraction(JPC_CastShapeCollector *self, float inFraction);
typedef struct JPC_CollideShapeCollector JPC_CollideShapeCollector;
typedef struct JPC_CollideShapeCollectorFns {
 void (*Reset)(void *self);
 void (*AddHit)(void *self, JPC_CollideShapeCollector *base, const JPC_CollideShapeResult *Result);
} JPC_CollideShapeCollectorFns;
 JPC_CollideShapeCollector* JPC_CollideShapeCollector_new(
 void *self,
 JPC_CollideShapeCollectorFns fns);
 void JPC_CollideShapeCollector_delete(JPC_CollideShapeCollector* object);
 void JPC_CollideShapeCollector_UpdateEarlyOutFraction(JPC_CollideShapeCollector *self, float inFraction);
typedef struct JPC_BodyManager_DrawSettings {
 bool mDrawGetSupportFunction;
 bool mDrawSupportDirection;
 bool mDrawGetSupportingFace;
 bool mDrawShape;
 bool mDrawShapeWireframe;
 JPC_ShapeColor mDrawShapeColor;
 bool mDrawBoundingBox;
 bool mDrawCenterOfMassTransform;
 bool mDrawWorldTransform;
 bool mDrawVelocity;
 bool mDrawMassAndInertia;
 bool mDrawSleepStats;
 bool mDrawSoftBodyVertices;
 bool mDrawSoftBodyVertexVelocities;
 bool mDrawSoftBodyEdgeConstraints;
 bool mDrawSoftBodyBendConstraints;
 bool mDrawSoftBodyVolumeConstraints;
 bool mDrawSoftBodySkinConstraints;
 bool mDrawSoftBodyLRAConstraints;
 bool mDrawSoftBodyRods;
 bool mDrawSoftBodyRodStates;
 bool mDrawSoftBodyRodBendTwistConstraints;
 bool mDrawSoftBodyPredictedBounds;
 JPC_SoftBodyConstraintColor DrawSoftBodyConstraintColor;
} JPC_BodyManager_DrawSettings;
 void JPC_BodyManager_DrawSettings_default(JPC_BodyManager_DrawSettings* object);
typedef struct JPC_DebugRendererSimpleFns {
 void (*DrawLine)(const void *self, JPC_RVec3 inFrom, JPC_RVec3 inTo, JPC_Color inColor);
} JPC_DebugRendererSimpleFns;
typedef struct JPC_DebugRendererSimple JPC_DebugRendererSimple;
 JPC_DebugRendererSimple* JPC_DebugRendererSimple_new(
 const void *self,
 JPC_DebugRendererSimpleFns fns);
 void JPC_DebugRendererSimple_delete(JPC_DebugRendererSimple* object);
typedef struct JPC_String JPC_String;
 void JPC_String_delete(JPC_String* self);
 const char* JPC_String_c_str(JPC_String* self);
typedef struct JPC_Constraint JPC_Constraint;
 uint32_t JPC_Constraint_GetRefCount(const JPC_Constraint* self);
 void JPC_Constraint_AddRef(const JPC_Constraint* self);
 void JPC_Constraint_Release(const JPC_Constraint* self);
 void JPC_Constraint_delete(JPC_Constraint* self);
 uint32_t JPC_Constraint_GetConstraintPriority(const JPC_Constraint* self);
 void JPC_Constraint_SetConstraintPriority(JPC_Constraint* self, uint32_t inPriority);
 unsigned int JPC_Constraint_GetNumVelocityStepsOverride(const JPC_Constraint* self);
 void JPC_Constraint_SetNumVelocityStepsOverride(JPC_Constraint* self, unsigned int inN);
 unsigned int JPC_Constraint_GetNumPositionStepsOverride(const JPC_Constraint* self);
 void JPC_Constraint_SetNumPositionStepsOverride(JPC_Constraint* self, unsigned int inN);
 bool JPC_Constraint_GetEnabled(const JPC_Constraint* self);
 void JPC_Constraint_SetEnabled(JPC_Constraint* self, bool inEnabled);
 uint64_t JPC_Constraint_GetUserData(const JPC_Constraint* self);
 void JPC_Constraint_SetUserData(JPC_Constraint* self, uint64_t inUserData);
 void JPC_Constraint_NotifyShapeChanged(JPC_Constraint* self, JPC_BodyID inBodyID, JPC_Vec3 inDeltaCOM);
typedef struct JPC_TwoBodyConstraint JPC_TwoBodyConstraint;
 JPC_Body* JPC_TwoBodyConstraint_GetBody1(const JPC_TwoBodyConstraint* self);
 JPC_Body* JPC_TwoBodyConstraint_GetBody2(const JPC_TwoBodyConstraint* self);
 JPC_Mat44 JPC_TwoBodyConstraint_GetConstraintToBody1Matrix(const JPC_TwoBodyConstraint* self);
 JPC_Mat44 JPC_TwoBodyConstraint_GetConstraintToBody2Matrix(const JPC_TwoBodyConstraint* self);
typedef struct JPC_FixedConstraint JPC_FixedConstraint;
 JPC_Vec3 JPC_FixedConstraint_GetTotalLambdaPosition(const JPC_FixedConstraint* self);
 JPC_Vec3 JPC_FixedConstraint_GetTotalLambdaRotation(const JPC_FixedConstraint* self);
typedef struct JPC_DistanceConstraint JPC_DistanceConstraint;
 float JPC_DistanceConstraint_GetTotalLambdaPosition(const JPC_DistanceConstraint* self);
typedef struct JPC_SixDOFConstraint JPC_SixDOFConstraint;
 JPC_Vec3 JPC_SixDOFConstraint_GetTranslationLimitsMin(const JPC_SixDOFConstraint* self);
 JPC_Vec3 JPC_SixDOFConstraint_GetTranslationLimitsMax(const JPC_SixDOFConstraint* self);
 void JPC_SixDOFConstraint_SetTranslationLimits(JPC_SixDOFConstraint* self, JPC_Vec3 inLimitMin, JPC_Vec3 inLimitMax);
 JPC_Vec3 JPC_SixDOFConstraint_GetRotationLimitsMin(const JPC_SixDOFConstraint* self);
 JPC_Vec3 JPC_SixDOFConstraint_GetRotationLimitsMax(const JPC_SixDOFConstraint* self);
 void JPC_SixDOFConstraint_SetRotationLimits(JPC_SixDOFConstraint* self, JPC_Vec3 inLimitMin, JPC_Vec3 inLimitMax);
 float JPC_SixDOFConstraint_GetLimitsMin(const JPC_SixDOFConstraint* self, JPC_SixDOFConstraint_Axis inAxis);
 float JPC_SixDOFConstraint_GetLimitsMax(const JPC_SixDOFConstraint* self, JPC_SixDOFConstraint_Axis inAxis);
 bool JPC_SixDOFConstraint_IsFreeAxis(const JPC_SixDOFConstraint* self, JPC_SixDOFConstraint_Axis inAxis);
 void JPC_SixDOFConstraint_SetMaxFriction(JPC_SixDOFConstraint* self, JPC_SixDOFConstraint_Axis inAxis, float inFriction);
 float JPC_SixDOFConstraint_GetMaxFriction(const JPC_SixDOFConstraint* self, JPC_SixDOFConstraint_Axis inAxis);
 JPC_Quat JPC_SixDOFConstraint_GetRotationInConstraintSpace(const JPC_SixDOFConstraint* self);
 JPC_Vec3 JPC_SixDOFConstraint_GetTargetVelocityCS(const JPC_SixDOFConstraint* self);
 void JPC_SixDOFConstraint_SetTargetVelocityCS(JPC_SixDOFConstraint* self, JPC_Vec3 inVelocity);
 JPC_Vec3 JPC_SixDOFConstraint_GetTargetAngularVelocityCS(const JPC_SixDOFConstraint* self);
 void JPC_SixDOFConstraint_SetTargetAngularVelocityCS(JPC_SixDOFConstraint* self, JPC_Vec3 inAngularVelocity);
 JPC_Vec3 JPC_SixDOFConstraint_GetTargetPositionCS(const JPC_SixDOFConstraint* self);
 void JPC_SixDOFConstraint_SetTargetPositionCS(JPC_SixDOFConstraint* self, JPC_Vec3 inPosition);
 JPC_Quat JPC_SixDOFConstraint_GetTargetOrientationCS(const JPC_SixDOFConstraint* self);
 void JPC_SixDOFConstraint_SetTargetOrientationCS(JPC_SixDOFConstraint* self, JPC_Quat inOrientation);
 void JPC_SixDOFConstraint_SetTargetOrientationBS(JPC_SixDOFConstraint* self, JPC_Quat inOrientation);
 JPC_Vec3 JPC_SixDOFConstraint_GetTotalLambdaPosition(JPC_SixDOFConstraint* self);
 JPC_Vec3 JPC_SixDOFConstraint_GetTotalLambdaRotation(JPC_SixDOFConstraint* self);
 JPC_Vec3 JPC_SixDOFConstraint_GetTotalLambdaMotorTranslation(JPC_SixDOFConstraint* self);
 JPC_Vec3 JPC_SixDOFConstraint_GetTotalLambdaMotorRotation(JPC_SixDOFConstraint* self);
typedef struct JPC_HingeConstraint JPC_HingeConstraint;
 void JPC_HingeConstraint_SetMotorState(JPC_HingeConstraint* self, JPC_MotorState inState);
 JPC_MotorState JPC_HingeConstraint_GetMotorState(const JPC_HingeConstraint* self);
 void JPC_HingeConstraint_SetTargetAngularVelocity(JPC_HingeConstraint* self, float inAngularVelocity);
 float JPC_HingeConstraint_GetTargetAngularVelocity(const JPC_HingeConstraint* self);
 void JPC_HingeConstraint_SetTargetAngle(JPC_HingeConstraint* self, float inAngle);
 float JPC_HingeConstraint_GetTargetAngle(const JPC_HingeConstraint* self);
 JPC_Vec3 JPC_HingeConstraint_GetTotalLambdaPosition(const JPC_HingeConstraint* self);
 JPC_Vec2 JPC_HingeConstraint_GetTotalLambdaRotation(const JPC_HingeConstraint* self);
 float JPC_HingeConstraint_GetTotalLambdaRotationLimits(const JPC_HingeConstraint* self);
 float JPC_HingeConstraint_GetTotalLambdaMotor(const JPC_HingeConstraint* self);
typedef struct JPC_SliderConstraint JPC_SliderConstraint;
 void JPC_SliderConstraint_SetMotorState(JPC_SliderConstraint* self, JPC_MotorState inState);
 JPC_MotorState JPC_SliderConstraint_GetMotorState(const JPC_SliderConstraint* self);
 void JPC_SliderConstraint_SetTargetVelocity(JPC_SliderConstraint* self, float inVelocity);
 float JPC_SliderConstraint_GetTargetVelocity(const JPC_SliderConstraint* self);
 void JPC_SliderConstraint_SetTargetPosition(JPC_SliderConstraint* self, float inPosition);
 float JPC_SliderConstraint_GetTargetPosition(const JPC_SliderConstraint* self);
 JPC_Vec2 JPC_SliderConstraint_GetTotalLambdaPosition(const JPC_SliderConstraint* self);
 float JPC_SliderConstraint_GetTotalLambdaPositionLimits(const JPC_SliderConstraint* self);
 JPC_Vec3 JPC_SliderConstraint_GetTotalLambdaRotation(const JPC_SliderConstraint* self);
 float JPC_SliderConstraint_GetTotalLambdaMotor(const JPC_SliderConstraint* self);
typedef struct JPC_ConstraintSettings {
 bool Enabled;
 uint32_t ConstraintPriority;
 unsigned int NumVelocityStepsOverride;
 unsigned int NumPositionStepsOverride;
 float DrawConstraintSize;
 uint64_t UserData;
} JPC_ConstraintSettings;
typedef struct JPC_SpringSettings {
 JPC_SpringMode Mode;
 float FrequencyOrStiffness;
 float Damping;
} JPC_SpringSettings;
 void JPC_SpringSettings_default(JPC_SpringSettings* settings);
typedef struct JPC_MotorSettings {
 JPC_SpringSettings SpringSettings;
 float MinForceLimit;
 float MaxForceLimit;
 float MinTorqueLimit;
 float MaxTorqueLimit;
} JPC_MotorSettings;
 void JPC_MotorSettings_default(JPC_MotorSettings* settings);
typedef struct JPC_FixedConstraintSettings {
 JPC_ConstraintSettings ConstraintSettings;
 JPC_ConstraintSpace Space;
 bool AutoDetectPoint;
 JPC_RVec3 Point1;
 JPC_Vec3 AxisX1;
 JPC_Vec3 AxisY1;
 JPC_RVec3 Point2;
 JPC_Vec3 AxisX2;
 JPC_Vec3 AxisY2;
} JPC_FixedConstraintSettings;
 void JPC_FixedConstraintSettings_default(JPC_FixedConstraintSettings* settings);
 JPC_Constraint* JPC_FixedConstraintSettings_Create(
 const JPC_FixedConstraintSettings* self,
 JPC_Body* inBody1,
 JPC_Body* inBody2);
typedef struct JPC_SixDOFConstraintSettings {
 JPC_ConstraintSettings ConstraintSettings;
 JPC_ConstraintSpace Space;
 JPC_RVec3 Position1;
 JPC_Vec3 AxisX1;
 JPC_Vec3 AxisY1;
 JPC_RVec3 Position2;
 JPC_Vec3 AxisX2;
 JPC_Vec3 AxisY2;
 float MaxFriction[6];
 float LimitMin[6];
 float LimitMax[6];
} JPC_SixDOFConstraintSettings;
 void JPC_SixDOFConstraintSettings_default(JPC_SixDOFConstraintSettings* settings);
 JPC_Constraint* JPC_SixDOFConstraintSettings_Create(
 const JPC_SixDOFConstraintSettings* self,
 JPC_Body* inBody1,
 JPC_Body* inBody2);
typedef struct JPC_HingeConstraintSettings {
 JPC_ConstraintSettings ConstraintSettings;
 JPC_ConstraintSpace Space;
 JPC_RVec3 Point1;
 JPC_Vec3 HingeAxis1;
 JPC_Vec3 NormalAxis1;
 JPC_RVec3 Point2;
 JPC_Vec3 HingeAxis2;
 JPC_Vec3 NormalAxis2;
 float LimitsMin;
 float LimitsMax;
 JPC_SpringSettings LimitsSpringSettings;
 float MaxFrictionTorque;
 JPC_MotorSettings MotorSettings;
} JPC_HingeConstraintSettings;
 void JPC_HingeConstraintSettings_default(JPC_HingeConstraintSettings* settings);
 JPC_HingeConstraint* JPC_HingeConstraintSettings_Create(
 const JPC_HingeConstraintSettings* self,
 JPC_Body* inBody1,
 JPC_Body* inBody2);
typedef struct JPC_DistanceConstraintSettings {
 JPC_ConstraintSettings ConstraintSettings;
 JPC_ConstraintSpace Space;
 JPC_RVec3 Point1;
 JPC_RVec3 Point2;
 float MinDistance;
 float MaxDistance;
 JPC_SpringSettings LimitsSpringSettings;
} JPC_DistanceConstraintSettings;
 void JPC_DistanceConstraintSettings_default(JPC_DistanceConstraintSettings* settings);
 JPC_DistanceConstraint* JPC_DistanceConstraintSettings_Create(
 const JPC_DistanceConstraintSettings* self,
 JPC_Body* inBody1,
 JPC_Body* inBody2);
typedef struct JPC_SliderConstraintSettings {
 JPC_ConstraintSettings ConstraintSettings;
 JPC_ConstraintSpace Space;
 bool AutoDetectPoint;
 JPC_RVec3 Point1;
 JPC_Vec3 SliderAxis1;
 JPC_Vec3 NormalAxis1;
 JPC_RVec3 Point2;
 JPC_Vec3 SliderAxis2;
 JPC_Vec3 NormalAxis2;
 float LimitsMin;
 float LimitsMax;
 JPC_SpringSettings LimitsSpringSettings;
 float MaxFrictionForce;
 JPC_MotorSettings MotorSettings;
} JPC_SliderConstraintSettings;
 void JPC_SliderConstraintSettings_default(JPC_SliderConstraintSettings* settings);
 JPC_SliderConstraint* JPC_SliderConstraintSettings_Create(
 const JPC_SliderConstraintSettings* self,
 JPC_Body* inBody1,
 JPC_Body* inBody2);
typedef struct JPC_TriangleShapeSettings {
 uint64_t UserData;
 float Density;
 JPC_Vec3 V1;
 JPC_Vec3 V2;
 JPC_Vec3 V3;
 float ConvexRadius;
} JPC_TriangleShapeSettings;
 void JPC_TriangleShapeSettings_default(JPC_TriangleShapeSettings* object);
 bool JPC_TriangleShapeSettings_Create(const JPC_TriangleShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_MeshShapeSettings {
 uint64_t UserData;
 JPC_Float3* TriangleVertices;
 size_t TriangleVerticesLen;
 JPC_IndexedTriangle* IndexedTriangles;
 size_t IndexedTrianglesLen;
} JPC_MeshShapeSettings;
 void JPC_MeshShapeSettings_default(JPC_MeshShapeSettings* object);
 bool JPC_MeshShapeSettings_Create(const JPC_MeshShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_BoxShapeSettings {
 uint64_t UserData;
 float Density;
 JPC_Vec3 HalfExtent;
 float ConvexRadius;
} JPC_BoxShapeSettings;
 void JPC_BoxShapeSettings_default(JPC_BoxShapeSettings* object);
 bool JPC_BoxShapeSettings_Create(const JPC_BoxShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_SphereShapeSettings {
 uint64_t UserData;
 float Density;
 float Radius;
} JPC_SphereShapeSettings;
 void JPC_SphereShapeSettings_default(JPC_SphereShapeSettings* object);
 bool JPC_SphereShapeSettings_Create(const JPC_SphereShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_CapsuleShapeSettings {
 uint64_t UserData;
 float Density;
 float Radius;
 float HalfHeightOfCylinder;
} JPC_CapsuleShapeSettings;
 void JPC_CapsuleShapeSettings_default(JPC_CapsuleShapeSettings* object);
 bool JPC_CapsuleShapeSettings_Create(const JPC_CapsuleShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_CylinderShapeSettings {
 uint64_t UserData;
 float Density;
 float HalfHeight;
 float Radius;
 float ConvexRadius;
} JPC_CylinderShapeSettings;
 void JPC_CylinderShapeSettings_default(JPC_CylinderShapeSettings* object);
 bool JPC_CylinderShapeSettings_Create(const JPC_CylinderShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_PlaneShapeSettings {
 uint64_t UserData;
 JPC_Vec3 Normal;
 float Constant;
 float HalfExtent;
} JPC_PlaneShapeSettings;
 void JPC_PlaneShapeSettings_default(JPC_PlaneShapeSettings* object);
 bool JPC_PlaneShapeSettings_Create(const JPC_PlaneShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_ConvexHullShapeSettings {
 uint64_t UserData;
 float Density;
 const JPC_Vec3* Points;
 size_t PointsLen;
 float MaxConvexRadius;
 float MaxErrorConvexRadius;
 float HullTolerance;
} JPC_ConvexHullShapeSettings;
 void JPC_ConvexHullShapeSettings_default(JPC_ConvexHullShapeSettings* object);
 bool JPC_ConvexHullShapeSettings_Create(const JPC_ConvexHullShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_SubShapeSettings {
 const JPC_Shape* Shape;
 JPC_Vec3 Position;
 JPC_Quat Rotation;
 uint32_t UserData;
} JPC_SubShapeSettings;
 void JPC_SubShapeSettings_default(JPC_SubShapeSettings* object);
typedef struct JPC_StaticCompoundShapeSettings {
 uint64_t UserData;
 const JPC_SubShapeSettings* SubShapes;
 size_t SubShapesLen;
} JPC_StaticCompoundShapeSettings;
 void JPC_StaticCompoundShapeSettings_default(JPC_StaticCompoundShapeSettings* object);
 bool JPC_StaticCompoundShapeSettings_Create(const JPC_StaticCompoundShapeSettings* self, JPC_Shape** outShape, JPC_String** outError);
typedef struct JPC_MutableCompoundShape JPC_MutableCompoundShape;
 unsigned int JPC_MutableCompoundShape_AddShape(
 JPC_MutableCompoundShape* self,
 JPC_Vec3 inPosition,
 JPC_Quat inRotation,
 const JPC_Shape* inShape,
 uint32_t inUserData);
 void JPC_MutableCompoundShape_RemoveShape(JPC_MutableCompoundShape* self, unsigned int inIndex);
 void JPC_MutableCompoundShape_ModifyShape(JPC_MutableCompoundShape* self, unsigned int inIndex, JPC_Vec3 inPosition, JPC_Quat inRotation);
 void JPC_MutableCompoundShape_ModifyShape2(JPC_MutableCompoundShape* self, unsigned int inIndex, JPC_Vec3 inPosition, JPC_Quat inRotation, const JPC_Shape* inShape);
 void JPC_MutableCompoundShape_AdjustCenterOfMass(JPC_MutableCompoundShape* self);
typedef struct JPC_MutableCompoundShapeSettings {
 uint64_t UserData;
 const JPC_SubShapeSettings* SubShapes;
 size_t SubShapesLen;
} JPC_MutableCompoundShapeSettings;
 void JPC_MutableCompoundShapeSettings_default(JPC_MutableCompoundShapeSettings* object);
 bool JPC_MutableCompoundShapeSettings_Create(const JPC_MutableCompoundShapeSettings* self, JPC_MutableCompoundShape** outShape, JPC_String** outError);
typedef struct JPC_MassProperties {
 float Mass;
 JPC_Mat44 Inertia;
} JPC_MassProperties;
 void JPC_MassProperties_default(JPC_MassProperties* properties);
typedef struct JPC_BodyCreationSettings {
 JPC_RVec3 Position;
 JPC_Quat Rotation;
 JPC_Vec3 LinearVelocity;
 JPC_Vec3 AngularVelocity;
 uint64_t UserData;
 JPC_ObjectLayer ObjectLayer;
 JPC_MotionType MotionType;
 JPC_AllowedDOFs AllowedDOFs;
 bool AllowDynamicOrKinematic;
 bool IsSensor;
 bool CollideKinematicVsNonDynamic;
 bool UseManifoldReduction;
 bool ApplyGyroscopicForce;
 JPC_MotionQuality MotionQuality;
 bool EnhancedInternalEdgeRemoval;
 bool AllowSleeping;
 float Friction;
 float Restitution;
 float LinearDamping;
 float AngularDamping;
 float MaxLinearVelocity;
 float MaxAngularVelocity;
 float GravityFactor;
 unsigned int NumVelocityStepsOverride;
 unsigned int NumPositionStepsOverride;
 JPC_OverrideMassProperties OverrideMassProperties;
 JPC_MassProperties MassPropertiesOverride;
 float InertiaMultiplier;
 const JPC_Shape* Shape;
} JPC_BodyCreationSettings;
 void JPC_BodyCreationSettings_default(JPC_BodyCreationSettings* settings);
typedef struct JPC_BodyCreationSettings JPC_BodyCreationSettings;
 JPC_BodyCreationSettings* JPC_BodyCreationSettings_new();
 JPC_BodyID JPC_Body_GetID(const JPC_Body* self);
 JPC_BodyType JPC_Body_GetBodyType(const JPC_Body* self);
 bool JPC_Body_IsRigidBody(const JPC_Body* self);
 bool JPC_Body_IsSoftBody(const JPC_Body* self);
 bool JPC_Body_IsActive(const JPC_Body* self);
 bool JPC_Body_IsStatic(const JPC_Body* self);
 bool JPC_Body_IsKinematic(const JPC_Body* self);
 bool JPC_Body_IsDynamic(const JPC_Body* self);
 bool JPC_Body_CanBeKinematicOrDynamic(const JPC_Body* self);
 void JPC_Body_SetIsSensor(JPC_Body* self, bool inIsSensor);
 bool JPC_Body_IsSensor(const JPC_Body* self);
 void JPC_Body_SetCollideKinematicVsNonDynamic(JPC_Body* self, bool inCollide);
 bool JPC_Body_GetCollideKinematicVsNonDynamic(const JPC_Body* self);
 void JPC_Body_SetUseManifoldReduction(JPC_Body* self, bool inUseReduction);
 bool JPC_Body_GetUseManifoldReduction(const JPC_Body* self);
 bool JPC_Body_GetUseManifoldReductionWithBody(const JPC_Body* self, const JPC_Body* inBody2);
 void JPC_Body_SetApplyGyroscopicForce(JPC_Body* self, bool inApply);
 bool JPC_Body_GetApplyGyroscopicForce(const JPC_Body* self);
 void JPC_Body_SetEnhancedInternalEdgeRemoval(JPC_Body* self, bool inApply);
 bool JPC_Body_GetEnhancedInternalEdgeRemoval(const JPC_Body* self);
 bool JPC_Body_GetEnhancedInternalEdgeRemovalWithBody(const JPC_Body* self, const JPC_Body* inBody2);
 JPC_MotionType JPC_Body_GetMotionType(const JPC_Body* self);
 void JPC_Body_SetMotionType(JPC_Body* self, JPC_MotionType inMotionType);
 JPC_BroadPhaseLayer JPC_Body_GetBroadPhaseLayer(const JPC_Body* self);
 JPC_ObjectLayer JPC_Body_GetObjectLayer(const JPC_Body* self);
 bool JPC_Body_GetAllowSleeping(const JPC_Body* self);
 void JPC_Body_SetAllowSleeping(JPC_Body* self, bool inAllow);
 void JPC_Body_ResetSleepTimer(JPC_Body* self);
 float JPC_Body_GetFriction(const JPC_Body* self);
 void JPC_Body_SetFriction(JPC_Body* self, float inFriction);
 float JPC_Body_GetRestitution(const JPC_Body* self);
 void JPC_Body_SetRestitution(JPC_Body* self, float inRestitution);
 JPC_Vec3 JPC_Body_GetLinearVelocity(const JPC_Body* self);
 void JPC_Body_SetLinearVelocity(JPC_Body* self, JPC_Vec3 inLinearVelocity);
 void JPC_Body_SetLinearVelocityClamped(JPC_Body* self, JPC_Vec3 inLinearVelocity);
 JPC_Vec3 JPC_Body_GetAngularVelocity(const JPC_Body* self);
 void JPC_Body_SetAngularVelocity(JPC_Body* self, JPC_Vec3 inAngularVelocity);
 void JPC_Body_SetAngularVelocityClamped(JPC_Body* self, JPC_Vec3 inAngularVelocity);
 JPC_Vec3 JPC_Body_GetPointVelocityCOM(const JPC_Body* self, JPC_Vec3 inPointRelativeToCOM);
 JPC_Vec3 JPC_Body_GetPointVelocity(const JPC_Body* self, JPC_RVec3 inPoint);
 void JPC_Body_AddForce(JPC_Body* self, JPC_Vec3 inForce);
 void JPC_Body_AddForceAtPoint(JPC_Body* self, JPC_Vec3 inForce, JPC_RVec3 inPosition);
 void JPC_Body_AddTorque(JPC_Body* self, JPC_Vec3 inTorque);
 JPC_Vec3 JPC_Body_GetAccumulatedForce(const JPC_Body* self);
 JPC_Vec3 JPC_Body_GetAccumulatedTorque(const JPC_Body* self);
 void JPC_Body_ResetForce(JPC_Body* self);
 void JPC_Body_ResetTorque(JPC_Body* self);
 void JPC_Body_ResetMotion(JPC_Body* self);
 void JPC_Body_GetInverseInertia(const JPC_Body* self, JPC_Mat44* outMatrix);
 void JPC_Body_AddImpulse(JPC_Body* self, JPC_Vec3 inImpulse);
 void JPC_Body_AddImpulse2(JPC_Body* self, JPC_Vec3 inImpulse, JPC_RVec3 inPosition);
 void JPC_Body_AddAngularImpulse(JPC_Body* self, JPC_Vec3 inAngularImpulse);
 void JPC_Body_MoveKinematic(JPC_Body* self, JPC_RVec3 inTargetPosition, JPC_Quat inTargetRotation, float inDeltaTime);
 bool JPC_Body_ApplyBuoyancyImpulse(JPC_Body* self, JPC_RVec3 inSurfacePosition, JPC_Vec3 inSurfaceNormal, float inBuoyancy, float inLinearDrag, float inAngularDrag, JPC_Vec3 inFluidVelocity, JPC_Vec3 inGravity, float inDeltaTime);
 bool JPC_Body_IsInBroadPhase(const JPC_Body* self);
 bool JPC_Body_IsCollisionCacheInvalid(const JPC_Body* self);
 const JPC_Shape* JPC_Body_GetShape(const JPC_Body* self);
 JPC_RVec3 JPC_Body_GetPosition(const JPC_Body* self);
 JPC_Quat JPC_Body_GetRotation(const JPC_Body* self);
 JPC_RMat44 JPC_Body_GetWorldTransform(const JPC_Body* self);
 JPC_RVec3 JPC_Body_GetCenterOfMassPosition(const JPC_Body* self);
 JPC_RMat44 JPC_Body_GetCenterOfMassTransform(const JPC_Body* self);
 JPC_RMat44 JPC_Body_GetInverseCenterOfMassTransform(const JPC_Body* self);
 uint64_t JPC_Body_GetUserData(const JPC_Body* self);
 void JPC_Body_SetUserData(JPC_Body* self, uint64_t inUserData);
 JPC_Vec3 JPC_Body_GetWorldSpaceSurfaceNormal(const JPC_Body* self, JPC_SubShapeID inSubShapeID, JPC_RVec3 inPosition);
typedef struct JPC_BodyLockInterface JPC_BodyLockInterface;
typedef struct JPC_BodyLockRead JPC_BodyLockRead;
 JPC_BodyLockRead* JPC_BodyLockRead_new(const JPC_BodyLockInterface* interface, JPC_BodyID bodyID);
 void JPC_BodyLockRead_delete(JPC_BodyLockRead* self);
 bool JPC_BodyLockRead_Succeeded(JPC_BodyLockRead* self);
 const JPC_Body* JPC_BodyLockRead_GetBody(JPC_BodyLockRead* self);
typedef struct JPC_BodyLockWrite JPC_BodyLockWrite;
 JPC_BodyLockWrite* JPC_BodyLockWrite_new(const JPC_BodyLockInterface* interface, JPC_BodyID bodyID);
 void JPC_BodyLockWrite_delete(JPC_BodyLockWrite* self);
 bool JPC_BodyLockWrite_Succeeded(JPC_BodyLockWrite* self);
 JPC_Body* JPC_BodyLockWrite_GetBody(JPC_BodyLockWrite* self);
typedef struct JPC_BodyLockMultiRead JPC_BodyLockMultiRead;
 JPC_BodyLockMultiRead* JPC_BodyLockMultiRead_new(
 const JPC_BodyLockInterface* interface,
 const JPC_BodyID *inBodyIDs,
 int inNumber);
 void JPC_BodyLockMultiRead_delete(JPC_BodyLockMultiRead* self);
 const JPC_Body* JPC_BodyLockMultiRead_GetBody(JPC_BodyLockMultiRead* self, int inBodyIndex);
typedef struct JPC_BodyLockMultiWrite JPC_BodyLockMultiWrite;
 JPC_BodyLockMultiWrite* JPC_BodyLockMultiWrite_new(
 const JPC_BodyLockInterface* interface,
 const JPC_BodyID *inBodyIDs,
 int inNumber);
 void JPC_BodyLockMultiWrite_delete(JPC_BodyLockMultiWrite* self);
 JPC_Body* JPC_BodyLockMultiWrite_GetBody(JPC_BodyLockMultiWrite* self, int inBodyIndex);
typedef struct JPC_BodyInterface JPC_BodyInterface;
 JPC_Body* JPC_BodyInterface_CreateBody(JPC_BodyInterface* self, const JPC_BodyCreationSettings* inSettings);
 JPC_Body* JPC_BodyInterface_CreateBodyWithID(JPC_BodyInterface *self, JPC_BodyID inBodyID, const JPC_BodyCreationSettings* inSettings);
 JPC_Body* JPC_BodyInterface_CreateBodyWithoutID(const JPC_BodyInterface *self, const JPC_BodyCreationSettings* inSettings);
 void JPC_BodyInterface_DestroyBodyWithoutID(const JPC_BodyInterface *self, JPC_Body *inBody);
 bool JPC_BodyInterface_AssignBodyID(JPC_BodyInterface *self, JPC_Body *ioBody);
 JPC_Body* JPC_BodyInterface_UnassignBodyID(JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_UnassignBodyIDs(JPC_BodyInterface *self, const JPC_BodyID *inBodyIDs, int inNumber, JPC_Body **outBodies);
 void JPC_BodyInterface_DestroyBody(JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_DestroyBodies(JPC_BodyInterface *self, const JPC_BodyID *inBodyIDs, int inNumber);
 void JPC_BodyInterface_AddBody(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Activation inActivationMode);
 void JPC_BodyInterface_RemoveBody(JPC_BodyInterface *self, JPC_BodyID inBodyID);
 bool JPC_BodyInterface_IsAdded(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 JPC_BodyID JPC_BodyInterface_CreateAndAddBody(JPC_BodyInterface *self, const JPC_BodyCreationSettings* inSettings, JPC_Activation inActivationMode);
 void* JPC_BodyInterface_AddBodiesPrepare(JPC_BodyInterface *self, JPC_BodyID *ioBodies, int inNumber);
 void JPC_BodyInterface_AddBodiesFinalize(JPC_BodyInterface *self, JPC_BodyID *ioBodies, int inNumber, void* inAddState, JPC_Activation inActivationMode);
 void JPC_BodyInterface_AddBodiesAbort(JPC_BodyInterface *self, JPC_BodyID *ioBodies, int inNumber, void* inAddState);
 void JPC_BodyInterface_RemoveBodies(JPC_BodyInterface *self, JPC_BodyID *ioBodies, int inNumber);
 void JPC_BodyInterface_ActivateBody(JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_ActivateBodies(JPC_BodyInterface *self, const JPC_BodyID *inBodyIDs, int inNumber);
 void JPC_BodyInterface_DeactivateBody(JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_DeactivateBodies(JPC_BodyInterface *self, JPC_BodyID *inBodyIDs, int inNumber);
 bool JPC_BodyInterface_IsActive(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 const JPC_Shape* JPC_BodyInterface_GetShape(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetShape(const JPC_BodyInterface *self, JPC_BodyID inBodyID, const JPC_Shape *inShape, bool inUpdateMassProperties, JPC_Activation inActivationMode);
 void JPC_BodyInterface_NotifyShapeChanged(const JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inPreviousCenterOfMass, bool inUpdateMassProperties, JPC_Activation inActivationMode);
 void JPC_BodyInterface_SetObjectLayer(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_ObjectLayer inLayer);
 JPC_ObjectLayer JPC_BodyInterface_GetObjectLayer(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetPositionAndRotation(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 inPosition, JPC_Quat inRotation, JPC_Activation inActivationMode);
 void JPC_BodyInterface_SetPositionAndRotationWhenChanged(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 inPosition, JPC_Quat inRotation, JPC_Activation inActivationMode);
 void JPC_BodyInterface_GetPositionAndRotation(const JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 *outPosition, JPC_Quat *outRotation);
 void JPC_BodyInterface_SetPosition(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 inPosition, JPC_Activation inActivationMode);
 JPC_RVec3 JPC_BodyInterface_GetPosition(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 JPC_RVec3 JPC_BodyInterface_GetCenterOfMassPosition(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetRotation(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Quat inRotation, JPC_Activation inActivationMode);
 JPC_Quat JPC_BodyInterface_GetRotation(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 JPC_RMat44 JPC_BodyInterface_GetWorldTransform(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 JPC_RMat44 JPC_BodyInterface_GetCenterOfMassTransform(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_MoveKinematic(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 inTargetPosition, JPC_Quat inTargetRotation, float inDeltaTime);
 void JPC_BodyInterface_SetLinearAndAngularVelocity(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inLinearVelocity, JPC_Vec3 inAngularVelocity);
 void JPC_BodyInterface_GetLinearAndAngularVelocity(const JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 *outLinearVelocity, JPC_Vec3 *outAngularVelocity);
 void JPC_BodyInterface_SetLinearVelocity(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inLinearVelocity);
 JPC_Vec3 JPC_BodyInterface_GetLinearVelocity(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_AddLinearVelocity(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inLinearVelocity);
 void JPC_BodyInterface_AddLinearAndAngularVelocity(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inLinearVelocity, JPC_Vec3 inAngularVelocity);
 void JPC_BodyInterface_SetAngularVelocity(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inAngularVelocity);
 JPC_Vec3 JPC_BodyInterface_GetAngularVelocity(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 JPC_Vec3 JPC_BodyInterface_GetPointVelocity(const JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 inPoint);
 void JPC_BodyInterface_SetPositionRotationAndVelocity(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_RVec3 inPosition, JPC_Quat inRotation, JPC_Vec3 inLinearVelocity, JPC_Vec3 inAngularVelocity);
 void JPC_BodyInterface_AddForce(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inForce);
 void JPC_BodyInterface_AddForceAtPoint(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inForce, JPC_RVec3 inPoint);
 void JPC_BodyInterface_AddTorque(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inTorque);
 void JPC_BodyInterface_AddForceAndTorque(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inForce, JPC_Vec3 inTorque);
 void JPC_BodyInterface_AddImpulse(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inImpulse);
 void JPC_BodyInterface_AddImpulse3(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inImpulse, JPC_RVec3 inPoint);
 void JPC_BodyInterface_AddAngularImpulse(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Vec3 inAngularImpulse);
 JPC_BodyType JPC_BodyInterface_GetBodyType(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetMotionType(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_MotionType inMotionType, JPC_Activation inActivationMode);
 JPC_MotionType JPC_BodyInterface_GetMotionType(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetMotionQuality(JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_MotionQuality inMotionQuality);
 JPC_MotionQuality JPC_BodyInterface_GetMotionQuality(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_GetInverseInertia(const JPC_BodyInterface *self, JPC_BodyID inBodyID, JPC_Mat44 *outMatrix);
 void JPC_BodyInterface_SetRestitution(JPC_BodyInterface *self, JPC_BodyID inBodyID, float inRestitution);
 float JPC_BodyInterface_GetRestitution(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetFriction(JPC_BodyInterface *self, JPC_BodyID inBodyID, float inFriction);
 float JPC_BodyInterface_GetFriction(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetGravityFactor(JPC_BodyInterface *self, JPC_BodyID inBodyID, float inGravityFactor);
 float JPC_BodyInterface_GetGravityFactor(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetUseManifoldReduction(JPC_BodyInterface *self, JPC_BodyID inBodyID, bool inUseReduction);
 bool JPC_BodyInterface_GetUseManifoldReduction(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 uint64_t JPC_BodyInterface_GetUserData(const JPC_BodyInterface *self, JPC_BodyID inBodyID);
 void JPC_BodyInterface_SetUserData(const JPC_BodyInterface *self, JPC_BodyID inBodyID, uint64_t inUserData);
 void JPC_BodyInterface_InvalidateContactCache(JPC_BodyInterface *self, JPC_BodyID inBodyID);
typedef struct JPC_NarrowPhaseQuery JPC_NarrowPhaseQuery;
typedef struct JPC_NarrowPhaseQuery_CastRayArgs {
 JPC_RRayCast Ray;
 JPC_RayCastResult Result;
 const JPC_BroadPhaseLayerFilter *BroadPhaseLayerFilter;
 const JPC_ObjectLayerFilter *ObjectLayerFilter;
 const JPC_BodyFilter *BodyFilter;
 const JPC_ShapeFilter *ShapeFilter;
} JPC_NarrowPhaseQuery_CastRayArgs;
 bool JPC_NarrowPhaseQuery_CastRay(const JPC_NarrowPhaseQuery* self, JPC_NarrowPhaseQuery_CastRayArgs* args);
typedef struct JPC_RShapeCast {
 const JPC_Shape *Shape;
 JPC_Vec3 Scale;
 JPC_RMat44 CenterOfMassStart;
 JPC_Vec3 Direction;
} JPC_RShapeCast;
 void JPC_ShapeCastSettings_default(JPC_ShapeCastSettings* object);
typedef struct JPC_NarrowPhaseQuery_CastShapeArgs {
 JPC_RShapeCast ShapeCast;
 JPC_ShapeCastSettings Settings;
 JPC_RVec3 BaseOffset;
 JPC_CastShapeCollector *Collector;
 const JPC_BroadPhaseLayerFilter *BroadPhaseLayerFilter;
 const JPC_ObjectLayerFilter *ObjectLayerFilter;
 const JPC_BodyFilter *BodyFilter;
 const JPC_ShapeFilter *ShapeFilter;
} JPC_NarrowPhaseQuery_CastShapeArgs;
 void JPC_NarrowPhaseQuery_CastShape(const JPC_NarrowPhaseQuery* self, JPC_NarrowPhaseQuery_CastShapeArgs* args);
 void JPC_CollideShapeSettings_default(JPC_CollideShapeSettings* object);
typedef struct JPC_NarrowPhaseQuery_CollideShapeArgs {
 const JPC_Shape *Shape;
 JPC_Vec3 ShapeScale;
 JPC_RMat44 CenterOfMassTransform;
 JPC_CollideShapeSettings Settings;
 JPC_RVec3 BaseOffset;
 JPC_CollideShapeCollector *Collector;
 const JPC_BroadPhaseLayerFilter *BroadPhaseLayerFilter;
 const JPC_ObjectLayerFilter *ObjectLayerFilter;
 const JPC_BodyFilter *BodyFilter;
 const JPC_ShapeFilter *ShapeFilter;
} JPC_NarrowPhaseQuery_CollideShapeArgs;
 void JPC_NarrowPhaseQuery_CollideShape(const JPC_NarrowPhaseQuery* self, JPC_NarrowPhaseQuery_CollideShapeArgs* args);
typedef struct JPC_PhysicsSystem JPC_PhysicsSystem;
 JPC_PhysicsSystem* JPC_PhysicsSystem_new();
 void JPC_PhysicsSystem_delete(JPC_PhysicsSystem* object);
 void JPC_PhysicsSystem_Init(
 JPC_PhysicsSystem* self,
 unsigned int inMaxBodies,
 unsigned int inNumBodyMutexes,
 unsigned int inMaxBodyPairs,
 unsigned int inMaxContactConstraints,
 JPC_BroadPhaseLayerInterface* inBroadPhaseLayerInterface,
 JPC_ObjectVsBroadPhaseLayerFilter* inObjectVsBroadPhaseLayerFilter,
 JPC_ObjectLayerPairFilter* inObjectLayerPairFilter);
 void JPC_PhysicsSystem_OptimizeBroadPhase(JPC_PhysicsSystem* self);
 JPC_PhysicsUpdateError JPC_PhysicsSystem_Update(
 JPC_PhysicsSystem* self,
 float inDeltaTime,
 int inCollisionSteps,
 JPC_TempAllocatorImpl *inTempAllocator,
 JPC_JobSystem* inJobSystem);
 void JPC_PhysicsSystem_AddConstraint(JPC_PhysicsSystem* self, JPC_Constraint* constraint);
 void JPC_PhysicsSystem_RemoveConstraint(JPC_PhysicsSystem* self, JPC_Constraint* constraint);
 void JPC_PhysicsSystem_SetGravity(JPC_PhysicsSystem* self, JPC_Vec3 inGravity);
 JPC_Vec3 JPC_PhysicsSystem_GetGravity(const JPC_PhysicsSystem* self);
 JPC_BodyInterface* JPC_PhysicsSystem_GetBodyInterface(JPC_PhysicsSystem* self);
 JPC_BodyInterface* JPC_PhysicsSystem_GetBodyInterfaceNoLock(JPC_PhysicsSystem* self);
 const JPC_BodyLockInterface* JPC_PhysicsSystem_GetBodyLockInterface(JPC_PhysicsSystem* self);
 const JPC_NarrowPhaseQuery* JPC_PhysicsSystem_GetNarrowPhaseQuery(const JPC_PhysicsSystem* self);
 void JPC_PhysicsSystem_DrawBodies(
 JPC_PhysicsSystem* self,
 JPC_BodyManager_DrawSettings* inSettings,
 JPC_DebugRendererSimple* inRenderer,
 const void* inBodyFilter);
 void JPC_PhysicsSystem_DrawConstraints(
 JPC_PhysicsSystem* self,
 JPC_DebugRendererSimple* inRenderer);
 void JPC_PhysicsSystem_SetSimShapeFilter(JPC_PhysicsSystem* self, const JPC_SimShapeFilter* inShapeFilter);
 void JPC_PhysicsSystem_SetContactListener(JPC_PhysicsSystem* self, JPC_ContactListener* inContactListener);

JPC_BroadPhaseLayerInterface *NJ_CapasAmplias(void);
JPC_ObjectVsBroadPhaseLayerFilter *NJ_FiltroObjetoAmplia(void);
JPC_ObjectLayerPairFilter *NJ_FiltroObjetos(void);

]]
