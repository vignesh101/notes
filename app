<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Solar System Hand Control</title>
    <style>
        body { margin: 0; overflow: hidden; background-color: #050505; }
        video { display: none; }
        #info {
            position: absolute;
            top: 10px;
            left: 10px;
            color: white;
            font-family: 'Courier New', Courier, monospace;
            pointer-events: none;
            background: rgba(0,0,0,0.6);
            padding: 15px;
            border-radius: 8px;
            border: 1px solid #333;
        }
        #current-planet {
            color: #4db8ff;
            font-weight: bold;
            font-size: 1.2em;
        }
    </style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@mediapipe/camera_utils/camera_utils.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@mediapipe/control_utils/control_utils.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@mediapipe/drawing_utils/drawing_utils.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@mediapipe/hands/hands.js"></script>
</head>
<body>

    <div id="info">
        <h3>🌌 Solar System Controller</h3>
        <p>Current: <span id="current-planet">Sun</span></p>
        <hr style="border-color: #333;">
        <p>🖐 <b>Open Hand:</b> Move Object</p>
        <p>🤏 <b>Pinch:</b> Resize / Pulse</p>
        <p>✊ <b>Make Fist:</b> Next Planet</p>
    </div>
    <video id="input_video"></video>

<script>
    // --- CONFIGURATION ---
    const PARTICLE_COUNT = 4000; // Increased for better planet density
    const PARTICLE_SIZE = 0.12;
    
    // --- THREE.JS SETUP ---
    const scene = new THREE.Scene();
    // Add subtle fog for depth
    scene.fog = new THREE.FogExp2(0x000000, 0.02);

    const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
    camera.position.z = 35;

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.setPixelRatio(window.devicePixelRatio);
    document.body.appendChild(renderer.domElement);

    // --- PARTICLES SETUP ---
    const geometry = new THREE.BufferGeometry();
    const positions = new Float32Array(PARTICLE_COUNT * 3);
    const colors = new Float32Array(PARTICLE_COUNT * 3);
    const targetPositions = new Float32Array(PARTICLE_COUNT * 3);
    const targetColors = new Float32Array(PARTICLE_COUNT * 3);

    // Initial fill
    for (let i = 0; i < PARTICLE_COUNT * 3; i++) {
        positions[i] = (Math.random() - 0.5) * 100;
        targetPositions[i] = positions[i];
        colors[i] = 1;
        targetColors[i] = 1;
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));

    const material = new THREE.PointsMaterial({
        size: PARTICLE_SIZE,
        vertexColors: true,
        blending: THREE.AdditiveBlending,
        transparent: true,
        opacity: 0.9,
        sizeAttenuation: true
    });

    const particleSystem = new THREE.Points(geometry, material);
    scene.add(particleSystem);

    // --- SOLAR SYSTEM DATA ---
    // Defines geometry types and colors for every celestial body
    const SolarSystem = [
        { name: "Sun",      radius: 12, type: 'star',   color: [1.0, 0.6, 0.1] }, // Orange/Yellow
        { name: "Mercury",  radius: 2,  type: 'sphere', color: [0.7, 0.7, 0.7] }, // Grey
        { name: "Venus",    radius: 3.5,type: 'sphere', color: [0.9, 0.8, 0.6] }, // Pale Yellow
        { name: "Earth",    radius: 3.8,type: 'earth',  color: [0.2, 0.4, 1.0] }, // Blue/Green
        { name: "Mars",     radius: 2.5,type: 'sphere', color: [1.0, 0.2, 0.1] }, // Red
        { name: "Jupiter",  radius: 10, type: 'banded', color: [0.8, 0.6, 0.4] }, // Beige/Orange Bands
        { name: "Saturn",   radius: 8,  type: 'saturn', color: [0.9, 0.8, 0.5] }, // Gold + Rings
        { name: "Uranus",   radius: 6,  type: 'sphere', color: [0.4, 0.9, 0.9] }, // Cyan
        { name: "Neptune",  radius: 6,  type: 'sphere', color: [0.1, 0.2, 0.8] }, // Deep Blue
    ];

    let currentIndex = 0;

    // --- GEOMETRY GENERATORS ---
    function getSpherePoint(r) {
        // Random point inside sphere (volumetric) or on surface
        const theta = Math.random() * Math.PI * 2;
        const phi = Math.acos(2 * Math.random() - 1);
        // Distribute 80% on surface, 20% inside for volume
        const dist = Math.random() > 0.8 ? r * Math.cbrt(Math.random()) : r; 
        return {
            x: dist * Math.sin(phi) * Math.cos(theta),
            y: dist * Math.sin(phi) * Math.sin(theta),
            z: dist * Math.cos(phi)
        };
    }

    function setSolarShape(planetIndex) {
        const body = SolarSystem[planetIndex];
        document.getElementById('current-planet').innerText = body.name;
        
        const r = body.radius;
        const baseColor = body.color;

        for (let i = 0; i < PARTICLE_COUNT; i++) {
            let x, y, z, cr, cg, cb;
            
            // --- POSITION LOGIC ---
            if (body.type === 'saturn') {
                // 70% Planet, 30% Rings
                if (i < PARTICLE_COUNT * 0.7) {
                    const p = getSpherePoint(r);
                    x = p.x; y = p.y; z = p.z;
                } else {
                    // Rings
                    const angle = Math.random() * Math.PI * 2;
                    const ringDist = r * 1.4 + Math.random() * (r * 1.5);
                    x = ringDist * Math.cos(angle);
                    z = ringDist * Math.sin(angle); // Tilt handled by rotation later
                    y = (Math.random() - 0.5) * 0.5; // Thin disc
                }
            } else if (body.type === 'star') {
                // Sun: Volumetric with corona spikes
                const p = getSpherePoint(r);
                const spike = Math.random() > 0.95 ? 1.5 : 1.0; // Coronal ejections
                x = p.x * spike; y = p.y * spike; z = p.z * spike;
            } else {
                // Standard Sphere (Earth, Mars, etc)
                const p = getSpherePoint(r);
                x = p.x; y = p.y; z = p.z;
            }

            // --- COLOR LOGIC ---
            if (body.type === 'earth') {
                // Simple noise approximation for Earth continents vs ocean
                const noise = Math.sin(x*0.5) * Math.cos(y*0.5);
                if (noise > 0.3) { // Land (Greenish)
                    cr = 0.2; cg = 0.8; cb = 0.3;
                } else { // Ocean (Blue)
                    cr = 0.1; cg = 0.3; cb = 0.9;
                }
                // Add polar caps
                if (Math.abs(y) > r * 0.85) { cr=1; cg=1; cb=1; } 
            } else if (body.type === 'banded') {
                // Jupiter stripes based on Y height
                const bands = Math.sin(y * 1.5);
                cr = baseColor[0] + bands * 0.1;
                cg = baseColor[1] + bands * 0.05;
                cb = baseColor[2];
            } else {
                // Solid color with slight variation
                const variation = (Math.random() - 0.5) * 0.2;
                cr = baseColor[0] + variation;
                cg = baseColor[1] + variation;
                cb = baseColor[2] + variation;
            }

            // Set Targets
            const idx = i * 3;
            targetPositions[idx] = x;
            targetPositions[idx+1] = y;
            targetPositions[idx+2] = z;

            targetColors[idx] = Math.max(0, Math.min(1, cr));
            targetColors[idx+1] = Math.max(0, Math.min(1, cg));
            targetColors[idx+2] = Math.max(0, Math.min(1, cb));
        }
    }

    // Initialize with Sun
    setSolarShape(0);

    // --- INTERACTION STATE ---
    let handX = 0, handY = 0;
    let expansionFactor = 1;
    let isFistDetected = false;
    let lastFistTime = 0;

    // --- MEDIAPIPE ---
    const videoElement = document.getElementById('input_video');
    const hands = new Hands({locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`});

    hands.setOptions({ maxNumHands: 1, modelComplexity: 1, minDetectionConfidence: 0.6, minTrackingConfidence: 0.6 });

    hands.onResults(results => {
        if (results.multiHandLandmarks && results.multiHandLandmarks.length > 0) {
            const lm = results.multiHandLandmarks[0];
            
            // 1. Position
            const x = (1 - lm[9].x) * 2 - 1; // Middle finger knuckle for stability
            const y = (1 - lm[9].y) * 2 - 1;
            handX += (x * 25 - handX) * 0.1; // Smooth dampening
            handY += (y * 25 - handY) * 0.1;

            // 2. Pinch (Expansion)
            const d = Math.sqrt(Math.pow(lm[8].x - lm[4].x, 2) + Math.pow(lm[8].y - lm[4].y, 2));
            const targetExp = Math.max(0.2, Math.min(d * 5, 2.5));
            expansionFactor += (targetExp - expansionFactor) * 0.1;

            // 3. Fist Gesture (Switch Planet)
            // Check if fingertips are below knuckles
            const isFist = lm[8].y > lm[5].y && lm[12].y > lm[9].y && lm[16].y > lm[13].y;
            
            const now = Date.now();
            if (isFist && !isFistDetected && (now - lastFistTime > 1200)) {
                currentIndex = (currentIndex + 1) % SolarSystem.length;
                setSolarShape(currentIndex);
                lastFistTime = now;
            }
            isFistDetected = isFist;
        }
    });

    const cameraUtils = new Camera(videoElement, {
        onFrame: async () => await hands.send({image: videoElement}),
        width: 640, height: 480
    });
    cameraUtils.start();

    // --- ANIMATION LOOP ---
    function animate() {
        requestAnimationFrame(animate);

        const posAttr = geometry.attributes.position;
        const colAttr = geometry.attributes.color;

        // Move system to hand
        particleSystem.position.x = handX;
        particleSystem.position.y = handY;

        // Rotation logic
        particleSystem.rotation.y += 0.002;
        // Tilt Saturn/Uranus specific logic could go here, but global rotation works well enough for particles

        for (let i = 0; i < PARTICLE_COUNT; i++) {
            const idx = i * 3;

            // Lerp Color
            colAttr.array[idx]   += (targetColors[idx]   - colAttr.array[idx])   * 0.05;
            colAttr.array[idx+1] += (targetColors[idx+1] - colAttr.array[idx+1]) * 0.05;
            colAttr.array[idx+2] += (targetColors[idx+2] - colAttr.array[idx+2]) * 0.05;

            // Lerp Position
            let tx = targetPositions[idx];
            let ty = targetPositions[idx+1];
            let tz = targetPositions[idx+2];

            // Apply Hand Pinch (Expansion)
            tx *= expansionFactor;
            ty *= expansionFactor;
            tz *= expansionFactor;

            // Jitter for 'gas' effect on Sun or Gas Giants
            if (SolarSystem[currentIndex].type === 'star') {
                tx += (Math.random()-0.5) * 0.2;
                ty += (Math.random()-0.5) * 0.2;
                tz += (Math.random()-0.5) * 0.2;
            }

            posAttr.array[idx]   += (tx - posAttr.array[idx])   * 0.1;
            posAttr.array[idx+1] += (ty - posAttr.array[idx+1]) * 0.1;
            posAttr.array[idx+2] += (tz - posAttr.array[idx+2]) * 0.1;
        }

        posAttr.needsUpdate = true;
        colAttr.needsUpdate = true;

        renderer.render(scene, camera);
    }

    animate();
    window.addEventListener('resize', () => {
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(window.innerWidth, window.innerHeight);
    });
</script>
</body>
</html>
