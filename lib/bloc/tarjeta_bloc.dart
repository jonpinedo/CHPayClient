import 'package:flutter_bloc/flutter_bloc.dart';

// Estados
abstract class TarjetaState {}

class TarjetaInicial extends TarjetaState {}

class TarjetaLeyendo extends TarjetaState {}

class TarjetaValidada extends TarjetaState {
  final String uid;
  final String nombre;
  final double saldo;

  TarjetaValidada({
    required this.uid,
    required this.nombre,
    required this.saldo,
  });
}

class TarjetaError extends TarjetaState {
  final String mensaje;

  TarjetaError(this.mensaje);
}

// Eventos
abstract class TarjetaEvent {}

class LeerTarjeta extends TarjetaEvent {}

class ValidarTarjeta extends TarjetaEvent {
  final String uid;

  ValidarTarjeta(this.uid);
}

class ResetearTarjeta extends TarjetaEvent {}

// Bloc
class TarjetaBloc extends Bloc<TarjetaEvent, TarjetaState> {
  TarjetaBloc() : super(TarjetaInicial()) {
    on<LeerTarjeta>((event, emit) {
      emit(TarjetaLeyendo());
    });

    on<ValidarTarjeta>((event, emit) {
      // Este evento se maneja en el UI layer con APIService
    });

    on<ResetearTarjeta>((event, emit) {
      emit(TarjetaInicial());
    });
  }
}
