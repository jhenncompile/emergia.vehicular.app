import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de colores especializada para emergencias vehiculares
class AppColors {
  // Colores principales - tonalidad urgencia/emergencia
  static const Color primaryColor = Color(0xFFD32F2F);     // Rojo intenso
  static const Color secondaryColor = Color(0xFFF57C00);   // Naranja advertencia
  static const Color accentColor = Color(0xFFFFC107);      // Amarillo alerta
  
  // Fondos
  static const Color backgroundColor = Color(0xFFFFFFFF);
  static const Color scaffoldBackground = Color(0xFFFEF7E0); // Amarillo muy claro
  
  // Textos
  static const Color textDark = Color(0xFF2E2E2E);
  static const Color textLight = Color(0xFF757575);
  
  // Estados - para indicadores y notificaciones
  static const Color success = Color(0xFF4CAF50);  // Verde
  static const Color error = Color(0xFFD32F2F);    // Rojo
  static const Color warning = Color(0xFFFF9800);  // Naranja
  static const Color info = Color(0xFF2196F3);     // Azul
}

/// Tema global con colores de emergencia
final ThemeData appTheme = ThemeData(
  primaryColor: AppColors.primaryColor,
  scaffoldBackgroundColor: AppColors.backgroundColor,
  
  colorScheme: const ColorScheme.light(
    primary: AppColors.primaryColor,
    secondary: AppColors.secondaryColor,
    tertiary: AppColors.accentColor,
    surface: AppColors.backgroundColor,
    error: AppColors.error,
  ),

  textTheme: TextTheme(
    displayLarge: GoogleFonts.roboto(
      color: AppColors.textDark,
      fontWeight: FontWeight.bold,
      fontSize: 32,
    ),
    displayMedium: GoogleFonts.roboto(
      color: AppColors.textDark,
      fontWeight: FontWeight.bold,
      fontSize: 28,
    ),
    headlineSmall: GoogleFonts.poppins(
      color: AppColors.textDark,
      fontWeight: FontWeight.bold,
      fontSize: 24,
    ),
    bodyLarge: GoogleFonts.roboto(
      color: AppColors.textLight,
      fontSize: 16,
    ),
    bodyMedium: GoogleFonts.roboto(
      color: AppColors.textLight,
      fontSize: 14,
    ),
    bodySmall: GoogleFonts.inter(
      color: AppColors.textLight,
      fontSize: 12,
    ),
  ),
  
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
    ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
    ),
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primaryColor,
    foregroundColor: Colors.white,
    elevation: 0,
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.secondaryColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
    ),
    prefixIconColor: AppColors.secondaryColor,
    hintStyle: const TextStyle(color: AppColors.textLight),
  ),
);
