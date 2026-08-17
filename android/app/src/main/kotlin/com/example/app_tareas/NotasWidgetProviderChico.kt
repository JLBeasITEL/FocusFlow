package com.example.app_tareas

class NotasWidgetProviderChico : NotasWidgetProviderBase(
    layoutResId = R.layout.widget_notas_chico,
    cardIds = listOf(
        NotaCardIds(
            R.id.widget_notas_fila1,
            R.id.widget_notas_titulo1,
            R.id.widget_notas_cuerpo1,
            R.id.widget_notas_tiempo1,
        ),
        NotaCardIds(
            R.id.widget_notas_fila2,
            R.id.widget_notas_titulo2,
            R.id.widget_notas_cuerpo2,
            R.id.widget_notas_tiempo2,
        ),
    ),
)
