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

## Sección 6: Isolation Forest (4D)

Hiperparámetros:

- **ψ (tamaño de submuestra) = 256:** cada árbol se construye con 256 puntos sorteados de los 300 (`max_samples`).
- **m (cantidad de árboles) = 300** (`n_estimators`).
- `contamination=0.10` y `random_state=42`. Se entrena sobre las 4 features escaladas (`X_all`). El score es `-score_samples` y la flag sale de `predict == -1`.

`contamination=0.10` fija el presupuesto en 30 alertas (el 10% de 300). El umbral del score queda en 0.553.

### Minutos alertados y score por kind

En el ranking, 1 es el minuto más sospechoso de los 300.

| kind | n | flag IF | score mediana / máx | posición en el ranking (mín / mediana / máx) |
|---|---|---|---|---|
| micro_burst | 2 | 2 | 0.729 / 0.733 | 1 / 1.5 / 2 |
| incidente_5xx | 8 | 8 | 0.650 / 0.670 | 3 / 6.5 / 10 |
| cpu_latencia | 5 | 5 | 0.611 / 0.620 | 11 / 13 / 15 |
| timeouts | 4 | 4 | 0.564 / 0.578 | 20 / 24.5 / 30 |
| combo_sutil | 7 | **4** | 0.554 / 0.588 | 17 / 29 / 35 |
| spike_error | 3 | 0 | 0.534 / 0.550 | 32 / 38 / 39 |
| latencia_silenciosa | 6 | 1 | 0.524 / 0.587 | 18 / 41.5 / 66 |
| batch | 20 | **4** | 0.506 / 0.600 | 16 / 50 / 76 |
| degradacion | 18 | 0 | 0.463 / 0.511 | 46 / 81 / 224 |
| pico_carga | 8 | 0 | 0.427 / 0.520 | 44 / 110.5 / 155 |
| normal | 219 | **2** | 0.386 / 0.569 | 21 / 189 / 300 |

**Totales:** 30 alertas, de las cuales 24 son anomalías reales y 6 son falsos positivos (4 de batch y 2 normales). Precision 0.80, recall 0.45, F1 0.58.

### Observaciones

- **Primer detector que ve combo_sutil:** marca 4 de sus 7 minutos, y los 7 quedan entre las posiciones 17 y 35. Ningún univariado lo detectaba, porque lo raro está en la combinación: poco tráfico con error alto.
- **Cae en la trampa del batch:** marca 4 de sus 20 minutos. IF sí ve la CPU, y un 76% de CPU es poco frecuente en la muestra, aunque sea operación legítima.
- **Los 2 falsos positivos normales caen a las 08:00 y 08:01.** Es el arranque de la rampa matinal, con poco tráfico (~55 a 60 requests) y CPU baja (~25%). Están en el extremo inferior de la nube, donde hay pocos puntos, y por eso se aíslan rápido. Es el caso inverso a pico_carga: el borde de abajo de la nube termina pareciendo un outlier.
- **pico_carga no dispara:** su mejor minuto está en la posición 44. Lo pone en el extremo de la nube normal, no afuera de ella, porque sus 4 métricas suben en la proporción habitual.
- **Pierde anomalías de un solo eje que MAD sí ve:** spike_error queda en las posiciones 32 a 39, justo afuera del presupuesto, y latencia_silenciosa tiene 1 de 6. En 4D, que un solo eje se aleje pesa menos que en un detector dedicado a ese eje.
- **degradacion: 0 de 18.** El score sube junto con la rampa (de 0.38 a 0.51), pero no llega al umbral de 0.553.
- **El presupuesto limita el recall:** hay 53 anomalías y solo 30 alertas, así que aun acertando todas el recall máximo sería 30/53 = 0.57.

### Comparación con los univariados

| Detector | Alertas | Precision | Recall | F1 |
|---|---|---|---|---|
| k-sigma error | 10 | 1.00 | 0.19 | 0.32 |
| k-sigma lat | 8 | 1.00 | 0.15 | 0.26 |
| MAD error | 18 | 0.94 | 0.32 | 0.48 |
| MAD lat | 36 | 1.00 | 0.68 | **0.81** |
| Isolation Forest | 30 | 0.80 | 0.45 | 0.58 |
| One-Class SVM | 29 | 0.62 | 0.34 | 0.44 |

MAD lat tiene el mejor F1, porque 6 de los 8 kinds anómalos rompen la latencia. Igual, IF detecta combo_sutil, y ningún univariado lo ve.

## Sección 7: One-Class SVM (4D)

Parámetros: `kernel="rbf"`, `nu=0.10`, `gamma="scale"`. Con las features escaladas, gamma = 1 / (4 · var) = 0.25. Se entrena sobre `X_all`. El score es `-decision_function` y la flag sale de `predict == -1`, que equivale a f(x) < 0. El modelo quedó con 39 vectores de soporte.

### Minutos alertados y score por kind (comparado con IF)

| kind | n | flag OCSVM | flag IF | score mediana / máx | posición en el ranking (mín / mediana / máx) |
|---|---|---|---|---|---|
| micro_burst | 2 | 2 | 2 | 1.709 / 1.740 | 1 / 1.5 / 2 |
| spike_error | 3 | **2** | 0 | 0.028 / 0.117 | 8 / 18 / 38 |
| timeouts | 4 | 2 | 4 | 0.012 / 0.237 | 4 / 29 / 43 |
| incidente_5xx | 8 | **4** | 8 | 0.011 / 0.097 | 9 / 26 / 63 |
| latencia_silenciosa | 6 | **3** | 1 | 0.000 / 0.513 | 3 / 31.5 / 130 |
| cpu_latencia | 5 | 3 | 5 | 0.000 / 0.128 | 7 / 28 / 42 |
| combo_sutil | 7 | 1 | 4 | −0.138 / 0.056 | 14 / 57 / 68 |
| degradacion | 18 | 1 | 0 | −0.458 / 0.042 | 17 / 158.5 / 296 |
| batch | 20 | **5** | 4 | −0.136 / 0.222 | 5 / 57.5 / 127 |
| pico_carga | 8 | **2** | 0 | −0.197 / 0.043 | 16 / 69 / 161 |
| normal | 219 | **4** | 2 | −0.512 / 0.044 | 15 / 182 / 300 |

**Totales:** 29 alertas, de las cuales 18 son anomalías reales y 11 son falsos positivos (5 de batch, 2 de pico_carga y 4 normales). Precision 0.62, recall 0.34, F1 0.44.

### Falsos positivos

| timestamp | requests | error_rate | latency_ms | cpu_pct | kind |
|---|---|---|---|---|---|
| 08:01 | 62 | 0.0048 | 77.9 | 27.0 | normal |
| 08:04 | 58 | 0.0060 | 76.6 | 23.4 | normal |
| 08:25 | 78 | 0.0088 | 81.6 | 72.9 | batch |
| 08:26 | 86 | 0.0076 | 73.7 | 75.9 | batch |
| 08:29 | 87 | 0.0073 | 75.9 | 82.0 | batch |
| 10:19 | 178 | 0.0119 | 92.6 | 49.0 | normal |
| 11:18 | 183 | 0.0113 | 104.5 | 46.7 | pico_carga |
| 11:25 | 180 | 0.0124 | 99.7 | 53.1 | pico_carga |
| 11:42 | 145 | 0.0108 | 99.3 | 79.2 | batch |
| 11:46 | 165 | 0.0109 | 107.3 | 75.3 | batch |
| 12:18 | 139 | 0.0085 | 86.0 | 29.8 | normal |

Todos están en algún borde de la nube normal: poco tráfico a las 08:00, mucho tráfico (pico_carga y 10:19), CPU alta (batch) o CPU baja para su carga (12:18).

### Observaciones

- **Ranking y flag no coinciden.** La mayoría de las anomalías tienen score cerca de 0: la mediana de incidente_5xx es 0.011 y la de latencia_silenciosa es 0.000. Quedan prácticamente sobre la frontera, así que cualquier diferencia mínima decide si alertan o no. Esto se ve en la gráfica: el score oscila alrededor de la línea f(x) = 0.
- **La frontera envuelve parte de las anomalías.** Con `nu=0.10` y kernel RBF, el modelo arma una región que deja afuera alrededor del 10% de los puntos. Como entrenó con todos los minutos, anomalías incluidas, los grupos compactos de anomalías probablemente terminan cerca o adentro de esa región. El caso más claro es incidente_5xx: 8 minutos juntos con 37 requests y error de ~0.042, de los que OCSVM solo marca 4. IF los marca todos, porque igual se aíslan rápido.
- **Le gana a IF en anomalías de un solo eje:** spike_error (2 contra 0) y latencia_silenciosa (3 contra 1).
- **Pierde contra IF en combinaciones:** combo_sutil (1 contra 4), incidente_5xx (4 contra 8), timeouts (2 contra 4) y cpu_latencia (3 contra 5).
- **Cae más en las trampas:** 5 minutos de batch y, a diferencia de IF, 2 de pico_carga. Una frontera RBF ajustada a la nube normal corta también sus extremos legítimos.

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
No, con ninguno de los dos univariados. Con k-sigma el score máximo es 0.38 en error y 0.43 en latencia, igual que un minuto normal. Con MAD sube a 2.73 en error y 2.40 en latencia: queda arriba de casi todos los normales en el ranking, pero bajo el umbral. Su error rate (0.0132 a 0.0140) está justo debajo del umbral MAD de 0.0144. Lo raro de combo_sutil es la combinación de poco tráfico con error alto, y eso un detector de un solo eje no lo puede ver.

Los multivariados sí lo ponen arriba en el ranking:

- **Isolation Forest:** sus 7 minutos quedan entre las posiciones 17 y 35 de 300, y la flag se enciende en 4.
- **One-Class SVM:** lo ranquea peor, entre las posiciones 14 y 68 (mediana 57), y la flag se enciende en 1 solo minuto. Su score mediano es −0.138, adentro de la frontera.

IF es el que mejor lo ve. Igual, hasta con IF la mitad de los minutos queda en el ranking sin encender la flag.

**4. pico_carga contra incidente_5xx en el plano requests–error.**
En promedio, pico_carga está en (174 requests, error 0.0115) e incidente_5xx en (37 requests, error 0.042).

- **pico_carga está al borde de la nube:** es el extremo derecho de la franja normal. Tiene más tráfico que cualquier otro minuto, pero su error rate es el que corresponde a esa carga.
- **incidente_5xx está afuera:** tiene poco tráfico y un error rate 4 veces mayor de lo esperado. Ningún minuto normal se le acerca.

Las flags de los dos multivariados no responden igual a esa geometría:

- **Isolation Forest coincide:** 0 de 8 en pico_carga y 8 de 8 en incidente_5xx.
- **One-Class SVM no:** marca 2 de 8 en pico_carga (11:18 y 11:25, con 180 requests o más) y solo 4 de 8 en incidente_5xx. La frontera RBF corta el extremo legítimo de la nube y deja parcialmente adentro al grupo compacto del incidente.

**5. ¿Qué detector trata al batch como anomalía?**
Ni k-sigma ni MAD lo marcan en ninguno de sus 20 minutos. Ninguno de los dos mira CPU, que es el único eje que se mueve en el batch. El score MAD máximo del batch es 1.79 en error y 2.20 en latencia. Isolation Forest sí incluye cpu_pct y marca 4 de los 20 minutos de batch, con score máximo 0.600 y mejor posición 16 en el ranking. Un modo raro se parece a un outlier porque IF mide qué tan rápido se aísla un punto, y el batch es poco frecuente: 20 minutos con CPU de ~76%, contra un 38% típico. IF no sabe si es un modo planificado o una falla, solo ve que hay pocos puntos en esa zona.

One-Class SVM marca 5 de los 20 minutos, todavía más que IF, y uno de ellos (08:29, CPU 82%) queda en la posición 5 del ranking. Una frontera ajustada al volumen donde está la mayoría de los datos deja afuera cualquier zona poco poblada, sea una falla o un modo operativo.

Los dos multivariados se equivocan por la misma razón: un detector no supervisado mide qué tan raro es un punto, no si es malo. Para no marcar el batch habría que darle contexto, por ejemplo una feature que indique si hay un job programado o una ventana de mantenimiento conocida.

**6. Primer minuto de degradacion que enciende cada método.**
La degradación arranca a las 11:50.

- **k-sigma lat:** no enciende ninguno de los 18 minutos. Su score máximo es 2.55, a las 12:06, con 209 ms.
- **MAD lat:** el primer minuto que enciende es las **11:57** (154 ms, score 4.68). Desde ahí enciende los 11 minutos restantes. Entre 11:51 y 11:56 la latencia ya estaba en 124 a 134 ms, con scores de 2.1 a 2.96, sin cruzar el umbral.
- **Detectores de error:** ninguno la ve, porque la degradación no genera errores.
- **Isolation Forest:** no enciende ninguno de los 18 minutos. Su score sube con la rampa, de 0.38 a 0.51, pero no llega al umbral de 0.553. El mejor minuto queda en la posición 46 del ranking.
- **One-Class SVM:** enciende un solo minuto, las **12:02**, doce minutos después del arranque y con score 0.042, apenas sobre la frontera. El score no sube de forma pareja con la rampa: va de −0.78 a 0.04 y vuelve a bajar a −0.35 en el minuto siguiente.

MAD lat es el que antes la detecta, a las 11:57. Los multivariados la ven peor, porque la latencia sube sola mientras las otras 3 métricas siguen normales, y en 4D ese desvío de un solo eje pesa menos.

A un detector i.i.d., que evalúa cada minuto por separado, le falta memoria. Cada minuto de 11:51 a 11:56 parece apenas alto, y no tiene en cuenta que la latencia viene subiendo seis minutos seguidos. Un detector con contexto temporal la vería antes: uno que mire la tendencia o la pendiente, que acumule desvíos como CUSUM o EWMA, o que use una ventana de varios minutos como feature.

**7. ¿nu = 0.10 y contamination = 0.10 dan el mismo F1?**
No. Los dos usan un presupuesto parecido (30 alertas IF, 29 OCSVM), pero:

| Detector | Alertas | Correctas | Falsos positivos | Precision | Recall | F1 |
|---|---|---|---|---|---|---|
| Isolation Forest | 30 | 24 | 6 | 0.80 | 0.45 | **0.58** |
| One-Class SVM | 29 | 18 | 11 | 0.62 | 0.34 | 0.44 |

Coinciden en 18 minutos. 12 los marca solo IF y 11 solo OCSVM. Las diferencias aparecen en:

- **Combinaciones raras, donde gana IF:** incidente_5xx (8 contra 4), combo_sutil (4 contra 1), timeouts (4 contra 2) y cpu_latencia (5 contra 3).
- **Anomalías de un solo eje, donde gana OCSVM:** spike_error (2 contra 0), latencia_silenciosa (3 contra 1) y degradacion (1 contra 0).
- **Trampas, donde OCSVM gasta más presupuesto:** batch (5 contra 4), pico_carga (2 contra 0) y normales (4 contra 2).

El presupuesto es el mismo, pero cada método lo gasta distinto. IF lo gasta en los puntos que se aíslan rápido, que son los grupos de anomalías lejos de la nube. OCSVM lo gasta en los puntos que quedan del lado de afuera de su frontera, y esa frontera también pasa por los bordes legítimos de la nube. Como entrena con datos contaminados, parte de los grupos de anomalías terminan adentro.

### Exit ticket

_Pendiente._
