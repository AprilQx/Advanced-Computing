/**
 * @file Array_2D.h
 * @brief A generic 2D array class that uses flat memory layout for better performance
 * 
 * This class provides a 2D array interface with a flat underlying memory structure.
 * It offers improved cache performance and memory locality compared to 
 * traditional 2D arrays implemented as arrays of pointers.
 */

 #ifndef ARRAY_2D_H
 #define ARRAY_2D_H
 
 #include <iostream>
 #include <algorithm>
 #include <stdexcept>
 #include <cstring>
 
 /**
  * @class Array_2D
  * @brief Generic 2D array with flat memory layout
  * 
  * @tparam T The data type of the array elements
  */
 template <typename T>
 class Array_2D {
 private:
     int num_rows;    ///< Number of rows in the array
     int num_cols;    ///< Number of columns in the array
     T* data;         ///< Pointer to the flat data array
 
 public:
     /**
      * @brief Constructor for the Array_2D class
      * @param rows Number of rows
      * @param cols Number of columns
      */
     Array_2D(int rows, int cols);
 
     /**
      * @brief Copy constructor
      * @param other Array to copy from
      */
     Array_2D(const Array_2D& other);
 
     /**
      * @brief Move constructor
      * @param other Array to move from
      */
     Array_2D(Array_2D&& other) noexcept;
 
     /**
      * @brief Destructor
      */
     ~Array_2D();
 
     /**
      * @brief Copy assignment operator
      * @param other Array to copy from
      * @return Reference to this object
      */
     Array_2D& operator=(const Array_2D& other);
 
     /**
      * @brief Move assignment operator
      * @param other Array to move from
      * @return Reference to this object
      */
     Array_2D& operator=(Array_2D&& other) noexcept;
 
     /**
      * @brief Access operator for element at position (row, col)
      * @param row Row index
      * @param col Column index
      * @return Reference to the element
      */
     T& operator()(int row, int col);
 
     /**
      * @brief Const access operator for element at position (row, col)
      * @param row Row index
      * @param col Column index
      * @return Const reference to the element
      */
     const T& operator()(int row, int col) const;
 
     /**
      * @brief Fill the entire array with a value
      * @param value The value to fill with
      */
     void fill(const T& value);
 
     /**
      * @brief Swap the contents of two arrays
      * @param other Array to swap with
      */
     void swap(Array_2D& other) noexcept;
 
     /**
      * @brief Get the number of rows
      * @return Number of rows
      */
     int rows() const;
 
     /**
      * @brief Get the number of columns
      * @return Number of columns
      */
     int cols() const;
 
     /**
      * @brief Get direct pointer to the underlying data
      * @return Pointer to the first element
      */
     T* getData();
 
     /**
      * @brief Get const pointer to the underlying data
      * @return Const pointer to the first element
      */
     const T* getData() const;
 };
 
 #include "Array_2D.cpp"  // Include the implementation file
 
 #endif // ARRAY_2D_H