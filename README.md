# Advanced Radar DSP Framework 📡⚡

[![MATLAB](https://img.shields.io/badge/MATLAB-R2023a%20or%20newer-blue.svg)](https://www.mathworks.com/products/matlab.html)
[![Academic Project](https://img.shields.io/badge/Course-Digital%20Signal%20Processing-success.svg)](https://github.com/)
[![Status](https://img.shields.io/badge/Release-v1.0.0-orange.svg)]()

A comprehensive, modular MATLAB-based Radar Digital Signal Processing (DSP) framework designed to address the challenges of target detection and resolution under adverse, non-stationary clutter, thermal noise, and multi-target interference environments.

> **Course Assignment:** Complex Engineering Problem (CEP) | Digital Signal Processing
> **Author:** Hassan Khalid, Department of Computer Engineering
---

## ⚡ System Architecture & Processing Chain

The framework simulates a physical radar transceiver and processes the returned signals through a multi-stage DSP pipeline:
```text
  [ Active Transceiver ] ──> LFM Chirp Waveform Generation
            │
            ▼
     [ Target Scene ]  ──> Swerling Fluctuation Models & Range-Doppler Coupling
            │
            ▼
    [ Radar Receiver ] ──> Environmental Noise & Non-Stationary Clutter Injection
            │
            ▼
       [ Stage 1 ]     ──> Matched Filtering & Sidelobe Windowing
            │
            ▼
       [ Stage 2 ]     ──> Clutter Mitigation (3-Pulse MTI Filter)
            │
            ▼
       [ Stage 3 ]     ──> 2D Range-Doppler FFT Processing
            │
            ▼
       [ Stage 4 ]     ──> Adaptive CFAR Thresholding (CA, OS, GO CFAR)
```

## ⚙️ Radar & Scenario Parameters

The system is configured in the X-band with the following baseline physical and temporal parameters[cite: 111]:

### Radar Specifications
| Parameter | Symbol | Value | Context |
| :--- | :--- | :--- | :--- |
| **Carrier Frequency** | $f_c$ | $10\text{ GHz}$ | X-band operations [cite: 111] |
| **Sampling Frequency** | $f_s$ | $200\text{ MHz}$ | Dictates range bin sizing [cite: 111] |
| **Chirp Bandwidth** | $B$ | $50\text{ MHz}$ | Limits spatial resolution [cite: 60] |
| **Pulse Duration** | $T$ | $10\ \mu\text{s}$ | Active pulse width [cite: 115] |
| **Pulse Repetition Interval**| $PRI$ | $200\ \mu\text{s}$ | Yields unambiguous range [cite: 112] |
| **Coherent Processing** | $N_{\text{pulses}}$| $16$ | CPI integration length [cite: 85] |
| **Theoretical Resolution** | $\Delta R$ | $3.0\text{ m}$ | Defined by $\frac{c}{2B}$ [cite: 193] |
| **Max Unambiguous Range** | $R_{\text{max}}$ | $30.0\text{ km}$ | Pulse travel boundary [cite: 112] |

### Target Profiles & Kinematics
The simulation models three distinct targets to challenge spatial resolution limits and dynamic receiver range[cite: 39, 40]:

* **Target 1:** Range: $1500\text{ m}$ | Velocity: $+30\text{ m/s}$ | Mean RCS: $1.0\text{ m}^2$ [cite: 46, 47, 48]
* **Target 2:** Range: $1520\text{ m}$ | Velocity: $-20\text{ m/s}$ | Mean RCS: $0.8\text{ m}^2$ [cite: 49, 50, 51] *(Placed closely to test resolution boundaries [cite: 45])*
* **Target 3:** Range: $3000\text{ m}$ | Velocity: $0\text{ m/s}$ | Mean RCS: $1.5\text{ m}^2$ [cite: 52, 53, 54]

---

## 📖 Theoretical Background & Mathematical Modeling

### 1. Linear Frequency Modulation (LFM) & Pulse Compression
The complex baseband LFM pulse is modeled mathematically as:
$$s(t) = \text{rect}\left(\frac{t}{T}\right)\exp\left(j\pi\frac{B}{T}t^2\right) \quad \text{[cite: 164]}$$

The matched filter's impulse response is the time-reversed complex conjugate $h(t) = s^*(-t)$[cite: 167]. Convolving the received echo with $h(t)$ yields a compressed pulse width of $\tau \approx 1/B$ and a peak power processing gain of $10\log_{10}(BT)$ (approximately $27\text{ dB}$ for the baseline configuration)[cite: 168, 214].

### 2. Statistical Target Fluctuation (Swerling Models)
To simulate dynamic radar cross-section (RCS) fluctuations, the target returns are modeled using Chi-square probability density functions (PDFs) with $2m$ degrees of freedom[cite: 145]:
$$p(\sigma) = \frac{m}{\bar{\sigma}(m-1)!} \left(\frac{m\sigma}{\bar{\sigma}}\right)^{m-1} \exp\left(-\frac{m\sigma}{\bar{\sigma}}\right) \quad \text{[cite: 147]}$$

* **Swerling I & II ($m=1$):** Models complex targets with many scatterers of equal area (Rayleigh distributed)[cite: 76, 146]. Swerling I fluctuates scan-to-scan, whereas Swerling II decorrelates pulse-to-pulse[cite: 77].
* **Swerling III & IV ($m=2$):** Models targets with one dominant scatterer and several smaller ones[cite: 78, 148]. Swerling III fluctuates scan-to-scan, whereas Swerling IV fluctuates pulse-to-pulse[cite: 78, 125].

### 3. Moving Target Indication (MTI) Clutter Filter
To suppress stationary ground or sea clutter clutter at DC, a double delay-line (three-pulse) canceller is implemented[cite: 82, 133, 134]. The Z-domain transfer function and corresponding power gain are modeled as:
$$H(z) = (1-z^{-1})^2 = 1 - 2z^{-1} + z^{-2} \quad \text{[cite: 154]}$$
$$|H(\omega)|^2 = 16\sin^4\left(\frac{\omega T_{\text{pri}}}{2}\right) \quad \text{[cite: 156]}$$

This response provides high stop-band attenuation near DC to isolate weak moving targets from dominant clutter[cite: 134, 157].

### 4. Constant False Alarm Rate (CFAR) Detection
CFAR algorithms adaptively set thresholds to handle non-homogeneous, non-stationary background noise and clutter[cite: 30, 88]:
* **Cell-Averaging (CA-CFAR):** Estimates noise by averaging leading and lagging training cells[cite: 89, 142]. For exponentially distributed noise, the threshold scaling factor $\alpha$ is given by:
    $$\alpha = N\left(P_{\text{fa}}^{-1/N} - 1\right) \quad \text{[cite: 169]}$$
* **Ordered-Statistic (OS-CFAR):** Sorts training samples and selects a representative rank (e.g., $75$th percentile) to mitigate target masking in dense scenarios[cite: 92, 211].
* **Greatest-Of (GO-CFAR):** Sets the threshold based on the maximum average of the leading vs. lagging window to control false alarms at clutter boundaries[cite: 93].

---

## 📊 CFAR Comparative Analysis

The processing pipeline evaluates the tradeoffs of each CFAR detector under distinct environmental conditions[cite: 201]:

| Environmental Condition | CA-CFAR [cite: 203] | OS-CFAR [cite: 204] | GO-CFAR [cite: 205] |
| :--- | :--- | :--- | :--- |
| **Homogeneous Noise** | 🟢 **Optimal** (Highest $P_d$) [cite: 221] | 🟡 Slightly lower $P_d$ [cite: 222] | 🟡 Moderate $P_d$ [cite: 223] |
| **Clutter Edges** | 🔴 High False Alarm Rate [cite: 179] | 🟢 **Robust** (Stable threshold) [cite: 180] | 🟢 **Excellent** (No false alarms) [cite: 181] |
| **Multi-Target Scenarios** | 🔴 Target Masking (Misses weak targets) [cite: 207, 210] | 🟢 **Robust** (Resolves close targets) [cite: 208, 211] | 🔴 Severe Target Masking [cite: 209, 212] |

---

## 🎨 Global Dark-Theme Visualizations

This project implements a **unified white-on-black plotting architecture** by modifying MATLAB's global root property manager (`groot`). This ensures all generated figures have high-contrast visual appeal:

1.  **Waveform Analysis:** Captures the real-part chirp waveform, phase trajectory, and power spectral density (PSD).
2.  **Ambiguity Function:** Displays the delay-Doppler response and zero-Doppler cuts to evaluate resolution limits.
3.  **Range-Doppler Map:** Illustrates target returns resolved concurrently in both radial velocity and range dimensions.
4.  **CFAR Detection Results:** Overlays the adaptive threshold curves against a summed 1D range profile, highlighting verified detections.
5.  **ROC Curves:** Compares analytical probabilities of detection ($P_d$) versus false alarm ($P_{\text{fa}}$).
6.  **Parametric Sensitivity Panels:** Sweeps SNR, bandwidth, guard cells, and window types to detail performance trade-offs.

---

## 🛠️ Getting Started

### Prerequisites
* **MATLAB** (R2023a or newer recommended)
* *Signal Processing Toolbox*

### Execution
1.  Clone the repository to your local machine:
    ```bash
    git clone [https://github.com/hassankhalid8/adaptive-radar-signal-processing.git](https://github.com/hassankhalid8/adaptive-radar-signal-processing.git)
    ```
2.  Navigate to the repository directory in MATLAB.
3.  Run the main script:
    ```matlab
    run('radar_dsp_framework.m')
    ```
4.  To customize the pipeline, open `radar_dsp_framework.m` and modify parameters inside the configuration block in **Section 0** (e.g., set `cfg.cfar_type = 'OS'` or change `cfg.swerling_model`).

---

## 🎓 Academic Acknowledgments
This repository is compiled as part of the **CE363 Digital Signal Processing** course's Complex Engineering Problem (CEP) assignment[cite: 6]. 

### References
All algorithms, models, and systems are grounded in established radar literature, including Skolnik's *Introduction to Radar Systems* [cite: 266], Richards' *Fundamentals of Radar Signal Processing* [cite: 279], and Rohling's foundational paper on Ordered Statistic CFAR[cite: 275, 276].
