# Comparación de detectores: resultados y respuestas

Notebook: [comparacion_detectores_obligatorio.ipynb](comparacion_detectores_obligatorio.ipynb)

Dataset: 300 ventanas de 1 minuto, 53 anómalas (17.7%). Semilla 42.

| kind | n | ¿anómalo? |
|---|---|---|
| normal | 219 | no |
| batch | 20 | no (trampa) |
| degradacion | 18 | sí |
| incidente_5xx | 8 | sí |
| pico_carga | 8 | no (trampa) |
| combo_sutil | 7 | sí |
| latencia_silenciosa | 6 | sí |
| cpu_latencia | 5 | sí |
| timeouts | 4 | sí |
| spike_error | 3 | sí |
| micro_burst | 2 | sí |

---

## Sección 4: k-sigma (k = 3)

μ y σ se estiman sobre las 300 ventanas, con σ calculado con ddof=1.

| Feature | μ | σ | Umbral μ + 3σ | Alertas |
|---|---|---|---|---|
| error_rate | 0.0112 | 0.0072 | 0.0328 | 10 |
| latency_ms | 110.47 | 38.54 | 226.1 | 8 |

### Minutos alertados por kind

| kind | n | k-sigma error | k-sigma lat |
|---|---|---|---|
| incidente_5xx | 8 | 8 | 6 |
| micro_burst | 2 | 2 | 2 |
| spike_error | 3 | 0 | 0 |
| timeouts | 4 | 0 | 0 |
| latencia_silenciosa | 6 | 0 | 0 |
| cpu_latencia | 5 | 0 | 0 |
| degradacion | 18 | 0 | 0 |
| combo_sutil | 7 | 0 | 0 |
| batch | 20 | 0 | 0 |
| pico_carga | 8 | 0 | 0 |
| normal | 219 | 0 | 0 |

No hay falsos positivos. Solo se detectan 10 de las 53 anomalías, y siempre los dos kinds más extremos.

### Score por kind (mediana / máximo)

| kind | score error | score lat |
|---|---|---|
| micro_burst | 7.20 / 7.20 | 4.33 / 4.37 |
| incidente_5xx | 4.32 / 4.85 | 3.19 / 3.72 |
| latencia_silenciosa | 0.19 / 0.40 | 2.68 / **2.98** |
| cpu_latencia | 0.18 / 0.34 | 2.57 / 2.69 |
| degradacion | 0.24 / 0.52 | 1.20 / 2.55 |
| timeouts | 1.93 / 2.20 | 2.05 / 2.31 |
| spike_error | 1.58 / 1.88 | 0.68 / 0.69 |
| combo_sutil | 0.36 / 0.38 | 0.33 / 0.43 |
| batch | 0.24 / 0.59 | 0.43 / 0.95 |
| pico_carga | 0.04 / 0.19 | 0.15 / 0.32 |
| normal | 0.22 / 0.89 | 0.36 / 0.95 |

### Observaciones

- **σ inflada:** el error rate normal ronda 0.009 con ruido de aproximadamente 0.001. Aun así σ da 0.0072, unas 7 veces más. Lo que la infla es la propia contaminación de la muestra (incidente_5xx, micro_burst, timeouts y spikes). Con esa σ el umbral sube a 0.0328, y los `spike_error` (~0.023, score máximo 1.88) y los `timeouts` (~0.025, score máximo 2.20) quedan por debajo.
- **latencia_silenciosa casi entra:** su score máximo en latencia es 2.98, apenas debajo de k = 3. La σ de latencia (38.5 ms) también está inflada por incidente_5xx, micro_burst, cpu_latencia y degradacion.
- **Las trampas no disparan:** batch y pico_carga quedan con scores menores a 1.
  - batch solo altera la CPU (~76% contra ~38% normal), y k-sigma se aplicó solo a error_rate y latency_ms. Pasa desapercibido porque al detector le falta esa columna, no porque lo distinga como legítimo.
  - En pico_carga, la latencia (~104 ms) y el error rate (~0.012) quedan cerca del promedio general (110 ms y 0.011), así que el score es bajo. Además, suben en la misma proporción que la carga, como en cualquier minuto normal.

---

## Sección 5: MAD (k = 3)

Mediana y MAD se estiman sobre las 300 ventanas. La escala es 1.4826 · MAD.

| Feature | Mediana | MAD | Escala | σ k-sigma | Umbral mediana + 3·escala | Alertas |
|---|---|---|---|---|---|---|
| error_rate | 0.0097 | 0.0010 | 0.0016 | 0.0072 | 0.0144 | 18 |
| latency_ms | 99.22 | 7.84 | 11.62 | 38.54 | 134.1 | 36 |

### Minutos alertados por kind (k-sigma contra MAD)

| kind | n | k-sigma error | MAD error | k-sigma lat | MAD lat |
|---|---|---|---|---|---|
| incidente_5xx | 8 | 8 | 8 | 6 | 8 |
| micro_burst | 2 | 2 | 2 | 2 | 2 |
| spike_error | 3 | 0 | **3** | 0 | 0 |
| timeouts | 4 | 0 | **4** | 0 | **4** |
| latencia_silenciosa | 6 | 0 | 0 | 0 | **6** |
| cpu_latencia | 5 | 0 | 0 | 0 | **5** |
| degradacion | 18 | 0 | 0 | 0 | **11** |
| combo_sutil | 7 | 0 | 0 | 0 | 0 |
| batch | 20 | 0 | 0 | 0 | 0 |
| pico_carga | 8 | 0 | 0 | 0 | 0 |
| normal | 219 | 0 | **1** | 0 | 0 |

- **MAD error:** 18 alertas. 17 son anomalías reales y 1 es un falso positivo, un minuto normal con score 3.19.
- **MAD lat:** 36 alertas, todas anomalías reales. No tiene falsos positivos.

### Score MAD por kind (mediana / máximo)

| kind | score error | score lat |
|---|---|---|
| micro_burst | 34.41 / 34.42 | 15.33 / 15.46 |
| incidente_5xx | 21.01 / 23.50 | 11.55 / 13.31 |
| timeouts | 9.93 / 11.16 | 7.78 / 8.63 |
| spike_error | 8.28 / 9.70 | 1.27 / 1.31 |
| latencia_silenciosa | 0.11 / 0.93 | 9.85 / 10.87 |
| cpu_latencia | 0.64 / 0.66 | 9.49 / 9.89 |
| degradacion | 0.34 / 1.48 | 4.94 / 9.42 |
| combo_sutil | 2.61 / **2.73** | 2.08 / 2.40 |
| pico_carga | 1.05 / 1.84 | 0.46 / 0.89 |
| batch | 0.58 / 1.79 | 0.68 / 2.20 |
| normal | 0.62 / 3.19 | 0.54 / 2.19 |

### Observaciones

- **La escala robusta es mucho más chica.** En error_rate, la escala MAD (0.0016) es 4.5 veces menor que σ (0.0072). En latency_ms, 11.6 ms contra 38.5 ms, unas 3.3 veces menos. La mediana y la MAD casi no se mueven con los minutos anómalos, así que el umbral queda cerca del comportamiento normal real.
- **Lo que k-sigma no veía, MAD lo ve.** Aparecen spike_error (3 de 3), timeouts (4 de 4), latencia_silenciosa (6 de 6), cpu_latencia (5 de 5) y 11 de los 18 minutos de degradacion.
- **El costo es mínimo:** un solo falso positivo en 219 minutos normales, en error_rate. batch y pico_carga siguen sin disparar.
- **El falso positivo es un error rate bajo, no alto.** Es un minuto cerca de las 08:00 con error rate de ~0.005, debajo de la mediana. El score usa el valor absoluto |x − mediana|, así que alerta por los dos lados. En operación, que haya pocos errores no es un incidente, y convendría usar un score de un solo lado: (x − mediana) / escala > 3.
- **combo_sutil sigue invisible,** pero ahora está al borde: su error rate (0.0132 a 0.0140) queda justo debajo del umbral de 0.0144, con score máximo 2.73. Como dice el notebook, ningún eje por separado cruza 3 MAD.

## Sección 6: Isolation Forest

_Pendiente._

## Sección 7: One-Class SVM

_Pendiente._

## Sección 8: Comparación

_Pendiente._

---

## Respuestas a las preguntas

**1. σ de k-sigma contra la escala MAD en `error_rate`.**
En error_rate, σ = 0.0072 y la escala MAD = 0.0016, unas 4.5 veces menos. Los valores del micro_burst (~0.063), del incidente_5xx (~0.042), de los timeouts (~0.025) y de los spike_error (~0.023) están muy lejos de la media. Como σ suma desvíos al cuadrado, esos pocos minutos la inflan: el umbral de k-sigma sube a 0.0328 y los propios spikes quedan debajo (score máximo 1.88). La mediana (0.0097) y la MAD (0.0010) apenas se mueven, porque esos minutos son menos del 10% de la muestra y no cambian qué valor queda en el medio. Con MAD el umbral es 0.0144 y los 3 spikes se detectan, con scores de 8.3 a 9.7.

En latency_ms pasa lo mismo: σ = 38.5 ms contra una escala MAD de 11.6 ms, unas 3.3 veces menos. Ahí la inflan incidente_5xx, micro_burst, timeouts, cpu_latencia, latencia_silenciosa y degradacion. El umbral baja de 226 ms con k-sigma a 134 ms con MAD.

**2. Kinds que se encienden en error y no en latencia, y al revés.**
Con k-sigma casi no hay diferencia: solo se encienden incidente_5xx y micro_burst, en los dos ejes. La excepción son 2 minutos de incidente_5xx que se encienden en error y no en latencia.

Con MAD la separación es clara:

- **Solo en error:** spike_error (3 de 3). Su latencia es normal, con score 1.3.
- **Solo en latencia:** latencia_silenciosa (6 de 6), cpu_latencia (5 de 5) y degradacion (11 de 18).
- **En los dos:** incidente_5xx, micro_burst y timeouts.

latencia_silenciosa es el caso canónico porque solo se rompe un eje: la latencia sube a unos 213 ms y el error rate sigue normal (score MAD máximo 0.93). Un detector de error no la puede ver nunca. Uno de latencia la ve solo si su escala no está inflada: con k-sigma queda en 2.98 y no alerta, con MAD llega a 9.85 de mediana y alerta los 6 minutos.

**3. ¿combo_sutil cruza k = 3 en algún eje?**
_Parcial._ No, con ninguno de los dos univariados. Con k-sigma el score máximo es 0.38 en error y 0.43 en latencia, igual que un minuto normal. Con MAD sube a 2.73 en error y 2.40 en latencia: queda arriba de casi todos los normales en el ranking, pero bajo el umbral. Su error rate (0.0132 a 0.0140) está justo debajo del umbral MAD de 0.0144. Lo raro de combo_sutil es la combinación de poco tráfico con error alto, y eso un detector de un solo eje no lo puede ver. Falta revisar el ranking de IF y OCSVM.

**4. pico_carga contra incidente_5xx en el plano requests–error.**
_Pendiente (necesita IF y OCSVM)._

**5. ¿Qué detector trata al batch como anomalía?**
_Parcial._ Ni k-sigma ni MAD lo marcan en ninguno de sus 20 minutos. Ninguno de los dos mira CPU, que es el único eje que se mueve en el batch. El score MAD máximo del batch es 1.79 en error y 2.20 en latencia. Falta ver IF y OCSVM, que sí incluyen cpu_pct.

**6. Primer minuto de degradacion que enciende cada método.**
_Parcial._ La degradación arranca a las 11:50.

- **k-sigma lat:** no enciende ninguno de los 18 minutos. Su score máximo es 2.55, a las 12:06, con 209 ms.
- **MAD lat:** el primer minuto que enciende es las **11:57** (154 ms, score 4.68). Desde ahí enciende los 11 minutos restantes. Entre 11:51 y 11:56 la latencia ya estaba en 124 a 134 ms, con scores de 2.1 a 2.96, sin cruzar el umbral.
- **Detectores de error:** ninguno la ve, porque la degradación no genera errores.

A un detector i.i.d., que evalúa cada minuto por separado, le falta memoria. Cada minuto de 11:51 a 11:56 parece apenas alto, y no tiene en cuenta que la latencia viene subiendo seis minutos seguidos. Un detector con contexto temporal la vería antes: uno que mire la tendencia o la pendiente, que acumule desvíos como CUSUM o EWMA, o que use una ventana de varios minutos como feature.

**7. ¿nu = 0.10 y contamination = 0.10 dan el mismo F1?**
_Pendiente._

### Exit ticket

_Pendiente._
