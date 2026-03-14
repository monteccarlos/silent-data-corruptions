; ModuleID = '/tmp/autogen.bc'
source_filename = "/tmp/autogen.bc"

define void @autogen_SD0(ptr %0, ptr %1, ptr %2, i32 %3, i64 %4, i8 %5) {
BB:
  %A4 = alloca <4 x i16>, align 8
  %A3 = alloca <4 x i64>, align 32
  %A2 = alloca <2 x float>, align 8
  %A1 = alloca <8 x i16>, align 16
  %A = alloca <4 x i32>, align 16
  store <2 x i16> <i16 0, i16 -1>, ptr %A, align 4
  store <2 x double> <double 0.000000e+00, double 0xFFFFFFFFFFFFFFFF>, ptr %0, align 16
  store <8 x i16> zeroinitializer, ptr %0, align 16
  store <8 x i16> zeroinitializer, ptr %0, align 16
  store <8 x i32> <i32 0, i32 -1, i32 0, i32 -1, i32 0, i32 -1, i32 0, i32 -1>, ptr %0, align 32
  ret void
}