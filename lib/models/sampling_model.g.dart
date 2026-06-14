// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sampling_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SamplingModelAdapter extends TypeAdapter<SamplingModel> {
  @override
  final int typeId = 1;

  @override
  SamplingModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SamplingModel(
      id: fields[0] as String,
      fieldId: fields[1] as String,
      observerId: fields[2] as String,
      species: fields[3] as String,
      count: fields[4] as int,
      unit: fields[5] as String,
      method: fields[6] as String,
      latitude: fields[7] as double,
      longitude: fields[8] as double,
      createdAt: fields[9] as DateTime,
      isSynced: fields[10] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SamplingModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fieldId)
      ..writeByte(2)
      ..write(obj.observerId)
      ..writeByte(3)
      ..write(obj.species)
      ..writeByte(4)
      ..write(obj.count)
      ..writeByte(5)
      ..write(obj.unit)
      ..writeByte(6)
      ..write(obj.method)
      ..writeByte(7)
      ..write(obj.latitude)
      ..writeByte(8)
      ..write(obj.longitude)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SamplingModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
