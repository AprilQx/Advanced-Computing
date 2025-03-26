"""
Visualization script for MPI heat diffusion halo regions

This script reads the halo visualization output files from the MPI heat diffusion
simulation and creates color-coded visualizations of the domains and halo regions.
"""

import os
import glob
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as colors
import re
from matplotlib.patches import Rectangle

def read_halo_file(filename):
    """
    Read a halo visualization file and extract the data and metadata
    """
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    # Parse header metadata
    metadata = {}
    for line in lines[:4]:  # First 4 lines are metadata
        if line.startswith('#'):
            # Use regex to extract key-value pairs
            if "Rank:" in line:
                match = re.search(r'Rank: (\d+), Position: \((\d+),(\d+)\), Size: (\d+)x(\d+)', line)
                if match:
                    metadata['rank'] = int(match.group(1))
                    metadata['pos_x'] = int(match.group(2))
                    metadata['pos_y'] = int(match.group(3))
                    metadata['size_x'] = int(match.group(4))
                    metadata['size_y'] = int(match.group(5))
            elif "Domain with halos:" in line:
                match = re.search(r'Domain with halos: (\d+)x(\d+)', line)
                if match:
                    metadata['domain_with_halos_x'] = int(match.group(1))
                    metadata['domain_with_halos_y'] = int(match.group(2))
            elif "Neighbors:" in line:
                match = re.search(r'Neighbors: N=(-?\d+), E=(-?\d+), S=(-?\d+), W=(-?\d+)', line)
                if match:
                    metadata['neighbor_n'] = int(match.group(1))
                    metadata['neighbor_e'] = int(match.group(2))
                    metadata['neighbor_s'] = int(match.group(3))
                    metadata['neighbor_w'] = int(match.group(4))
    
    # Parse temperature data with halo markers
    data = []
    halo_mask = []
    
    for line in lines[4:]:  # Skip header
        if line.startswith('#') or not line.strip():
            continue
        
        row_data = []
        row_mask = []
        
        for item in line.strip().split():
            if item.startswith('h'):
                # This is a halo cell
                value = float(item[1:])  # Remove the 'h' prefix
                row_data.append(value)
                row_mask.append(1)  # 1 indicates halo cell
            else:
                # Regular cell
                value = float(item)
                row_data.append(value)
                row_mask.append(0)  # 0 indicates regular cell
        
        data.append(row_data)
        halo_mask.append(row_mask)
    
    return metadata, np.array(data), np.array(halo_mask)

def create_domain_visualization(frame_number, output_dir="visualizations"):
    """
    Create a visualization of all domains at a specific frame
    """
    # Make sure the output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    # Find all halo files for this frame
    file_pattern = f"output/mpi_halos/rank_*_frame_{frame_number}.txt"
    halo_files = glob.glob(file_pattern)
    
    if not halo_files:
        print(f"No halo files found for frame {frame_number}")
        return
    
    # Read all halo files to determine global grid size
    domains = []
    global_width = 0
    global_height = 0
    
    for filename in sorted(halo_files, key=lambda x: int(re.search(r'rank_(\d+)', x).group(1))):
        metadata, data, halo_mask = read_halo_file(filename)
        domains.append((metadata, data, halo_mask))
        
        # Update global size
        global_width = max(global_width, metadata['pos_x'] + metadata['size_x'])
        global_height = max(global_height, metadata['pos_y'] + metadata['size_y'])
    
    # Create figure
    plt.figure(figsize=(12, 10))
    
    # Create a custom colormap for temperatures
    cmap = plt.cm.get_cmap('hot')
    norm = colors.Normalize(vmin=20, vmax=100)  # Adjust based on temperature range
    
    # Plot each domain
    for metadata, data, halo_mask in domains:
        rank = metadata['rank']
        pos_x = metadata['pos_x']
        pos_y = metadata['pos_y']
        size_x = metadata['size_x']
        size_y = metadata['size_y']
        
        # Extract interior data (remove halos)
        interior_data = data[1:-1, 1:-1]
        
        # Plot the interior domain
        plt.imshow(interior_data, cmap=cmap, norm=norm, 
                   extent=[pos_x, pos_x + size_x, pos_y + size_y, pos_y],
                   interpolation='nearest', aspect='equal')
        
        # Add a rectangle around this domain
        rect = Rectangle((pos_x, pos_y), size_x, size_y, 
                          fill=False, edgecolor='white', linewidth=1)
        plt.gca().add_patch(rect)
        
        # Add rank number in the center of the domain
        plt.text(pos_x + size_x/2, pos_y + size_y/2, str(rank),
                 color='white', ha='center', va='center', fontsize=10)
    
    # Add colorbar
    plt.colorbar(plt.cm.ScalarMappable(norm=norm, cmap=cmap), 
                 label='Temperature', orientation='vertical')
    
    # Set plot properties
    plt.title(f'Heat Diffusion - Frame {frame_number} - Domain Decomposition')
    plt.xlabel('X')
    plt.ylabel('Y')
    plt.grid(True, color='gray', linestyle='--', linewidth=0.5, alpha=0.5)
    
    # Save the figure
    output_file = os.path.join(output_dir, f"domains_frame_{frame_number}.png")
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    plt.close()
    
    print(f"Created domain visualization for frame {frame_number}: {output_file}")
    
    # Now create a more detailed view showing halos
    plt.figure(figsize=(14, 12))
    
    # Create subplots for each domain with halos
    n_domains = len(domains)
    rows = int(np.ceil(np.sqrt(n_domains)))
    cols = int(np.ceil(n_domains / rows))
    
    for i, (metadata, data, halo_mask) in enumerate(domains):
        rank = metadata['rank']
        
        # Create subplot
        plt.subplot(rows, cols, i+1)
        
        # Create a masked array to highlight halos
        masked_data = np.ma.array(data, mask=halo_mask)
        
        # Plot the temperature data
        plt.imshow(data, cmap=cmap, norm=norm, interpolation='nearest')
        
        # Overlay halo mask
        plt.imshow(halo_mask, cmap=colors.ListedColormap(['none', 'black']), 
                   alpha=0.3, interpolation='nearest')
        
        # Add text labels for neighbor ranks
        neighbor_n = metadata['neighbor_n']
        neighbor_e = metadata['neighbor_e']
        neighbor_s = metadata['neighbor_s']
        neighbor_w = metadata['neighbor_w']
        
        h, w = data.shape
        plt.text(w/2, 0.5, f"N:{neighbor_n}", ha='center', va='center', color='white')
        plt.text(w-0.5, h/2, f"E:{neighbor_e}", ha='center', va='center', color='white')
        plt.text(w/2, h-0.5, f"S:{neighbor_s}", ha='center', va='center', color='white')
        plt.text(0.5, h/2, f"W:{neighbor_w}", ha='center', va='center', color='white')
        
        # Add title with rank information
        plt.title(f'Rank {rank} ({metadata["size_x"]}x{metadata["size_y"]})')
        plt.axis('off')
    
    plt.suptitle(f'Heat Diffusion - Frame {frame_number} - Domains with Halos', fontsize=16)
    plt.tight_layout()
    
    # Save the figure
    output_file = os.path.join(output_dir, f"halos_detail_frame_{frame_number}.png")
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    plt.close()
    
    print(f"Created halo detail visualization for frame {frame_number}: {output_file}")

def create_full_grid_visualization(frame_number, output_dir="visualizations"):
    """
    Create a visualization of the full grid with process boundaries
    """
    # Make sure the output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    # Check for the full decomposition file
    filename = f"output/mpi_halos/full_decomposition_frame_{frame_number}.txt"
    
    if not os.path.exists(filename):
        print(f"Full decomposition file not found for frame {frame_number}")
        return
    
    # Read the full grid data
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    # Extract metadata
    metadata = {}
    for line in lines[:4]:
        if line.startswith('#'):
            if "Domain decomposition:" in line:
                match = re.search(r'Domain decomposition: (\d+)x(\d+)', line)
                if match:
                    metadata['process_grid_x'] = int(match.group(1))
                    metadata['process_grid_y'] = int(match.group(2))
            elif "Global size:" in line:
                match = re.search(r'Global size: (\d+)x(\d+)', line)
                if match:
                    metadata['global_width'] = int(match.group(1))
                    metadata['global_height'] = int(match.group(2))
    
    # Parse data with boundary markers
    data = []
    boundaries_h = []  # Horizontal boundaries
    boundaries_v = []  # Vertical boundaries
    
    # Skip header lines
    data_lines = [line for line in lines[4:] if not line.startswith('#')]
    
    row_idx = 0
    for line in data_lines:
        # Check if this is a horizontal boundary line
        if all(c in ['-', ' '] for c in line.strip()):
            # Add a horizontal boundary at this position
            boundaries_h.append(row_idx - 0.5)
            continue
        
        # Process regular data row
        row_data = []
        col_markers = []
        
        items = line.strip().split()
        for i, item in enumerate(items):
            if item == '|':
                # This is a vertical boundary marker
                col_markers.append(i - 0.5 - len(col_markers))
            else:
                # This is a data value
                try:
                    value = float(item)
                    row_data.append(value)
                except ValueError:
                    # Skip non-numeric values
                    pass
        
        if row_data:
            data.append(row_data)
            if col_markers:
                boundaries_v.extend(col_markers)
        
        row_idx += 1
    
    # Ensure we have a valid 2D array
    data = np.array(data)
    
    # Create figure
    plt.figure(figsize=(12, 10))
    
    # Create a custom colormap for temperatures
    cmap = plt.cm.get_cmap('hot')
    norm = colors.Normalize(vmin=20, vmax=100)  # Adjust based on temperature range
    
    # Plot the temperature data
    plt.imshow(data, cmap=cmap, norm=norm, interpolation='nearest')
    
    # Add horizontal boundary lines
    for y in boundaries_h:
        plt.axhline(y=y, color='white', linestyle='-', linewidth=1)
    
    # Add vertical boundary lines
    for x in boundaries_v:
        plt.axvline(x=x, color='white', linestyle='-', linewidth=1)
    
    # Add grid markings for process boundaries
    process_grid_x = metadata.get('process_grid_x', 1)
    process_grid_y = metadata.get('process_grid_y', 1)
    
    # Add text to indicate rank
    h, w = data.shape
    cell_h = h / process_grid_y
    cell_w = w / process_grid_x
    
    for py in range(process_grid_y):
        for px in range(process_grid_x):
            rank = py * process_grid_x + px
            y_center = py * cell_h + cell_h / 2
            x_center = px * cell_w + cell_w / 2
            plt.text(x_center, y_center, str(rank), 
                    color='white', ha='center', va='center', fontsize=12)
    
    # Add colorbar
    plt.colorbar(plt.cm.ScalarMappable(norm=norm, cmap=cmap), 
                label='Temperature', orientation='vertical')
    
    # Set plot properties
    plt.title(f'Heat Diffusion - Frame {frame_number} - Full Grid with Process Boundaries')
    plt.xlabel('X')
    plt.ylabel('Y')
    
    # Save the figure
    output_file = os.path.join(output_dir, f"full_grid_frame_{frame_number}.png")
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    plt.close()
    
    print(f"Created full grid visualization for frame {frame_number}: {output_file}")

def main():
    """
    Main function to process all available frames
    """
    # Create output directory
    output_dir = "visualizations"
    os.makedirs(output_dir, exist_ok=True)
    
    # Find all available frame numbers
    file_pattern = "output/mpi_halos/rank_*_frame_*.txt"
    halo_files = glob.glob(file_pattern)
    
    if not halo_files:
        print("No halo visualization files found")
        return
    
    # Extract frame numbers
    frame_numbers = set()
    for filename in halo_files:
        match = re.search(r'frame_(\d+)\.txt, filename)
        if match:
            frame_numbers.add(int(match.group(1)))
    
    print(f"Found {len(frame_numbers)} frames to visualize")
    
    # Process each frame
    for frame in sorted(frame_numbers):
        print(f"Processing frame {frame}...")
        create_domain_visualization(frame, output_dir)
        create_full_grid_visualization(frame, output_dir)

if __name__ == "__main__":
    main()