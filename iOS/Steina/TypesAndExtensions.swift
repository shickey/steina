//
//  DataTypes.swift
//  Steina
//
//  Created by Sean Hickey on 5/23/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

typealias U8  = UInt8
typealias U16 = UInt16
typealias U32 = UInt32
typealias U64 = UInt64

typealias S8  = Int8
typealias S16 = Int16
typealias S32 = Int32
typealias S64 = Int64

typealias F32 = Float
typealias F64 = Double

typealias RawPtr = UnsafeMutableRawPointer
typealias Ptr<T> = UnsafeMutablePointer<T>

typealias U8Ptr  = UnsafeMutablePointer<UInt8>
typealias U16Ptr = UnsafeMutablePointer<UInt16>
typealias U32Ptr = UnsafeMutablePointer<UInt32>
typealias U64Ptr = UnsafeMutablePointer<UInt64>

typealias S8Ptr  = UnsafeMutablePointer<Int8>
typealias S16Ptr = UnsafeMutablePointer<Int16>
typealias S32Ptr = UnsafeMutablePointer<Int32>
typealias S64Ptr = UnsafeMutablePointer<Int64>

typealias F32Ptr = UnsafeMutablePointer<Float>
typealias F64Ptr = UnsafeMutablePointer<Double>

extension Int {
     var u8 :  U8 { get {return  U8(self)} }
    var u16 : U16 { get {return U16(self)} }
    var u32 : U32 { get {return U32(self)} }
    var u64 : U64 { get {return U64(self)} }
    
    var  s8 :  S8 { get {return  S8(self)} }
    var s16 : S16 { get {return S16(self)} }
    var s32 : S32 { get {return S32(self)} }
    var s64 : S64 { get {return S64(self)} }
    
    var kilobytes : Int { get { return self * 1024 }}
    var megabytes : Int { get { return self * 1024 * 1024 }}
    var gigabytes : Int { get { return self * 1024 * 1024 * 1024 }}
}
