package com.beasdev.focusflow

// 4 NotaCardIds (no 2, como Chico): Grande admite el modo "4 notas" del
// botón de alternancia del header (ver NotasWidgetProviderBase.kt). En modo
// "2 notas" fila3/fila4 simplemente no reciben item y quedan GONE, igual
// que cualquier tarjeta sin dato correspondiente.
class NotasWidgetProviderGrande : NotasWidgetProviderBase(
    layoutResId = R.layout.widget_notas_grande,
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
        NotaCardIds(
            R.id.widget_notas_fila3,
            R.id.widget_notas_titulo3,
            R.id.widget_notas_cuerpo3,
            R.id.widget_notas_tiempo3,
        ),
        NotaCardIds(
            R.id.widget_notas_fila4,
            R.id.widget_notas_titulo4,
            R.id.widget_notas_cuerpo4,
            R.id.widget_notas_tiempo4,
        ),
    ),
)
