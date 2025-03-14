/**
 * @file Array_2D.cpp
 * @brief Implementation of the Array_2D template class
 */

 #include <algorithm>
 #include <stdexcept>
 #include "Array_2D.h"
 
 /**
  * Constructor implementation
  */
 template <typename T>
 Array_2D<T>::Array_2D(int rows, int cols) : num_rows(rows), num_cols(cols) {
     if (rows <= 0 || cols <= 0) {
         throw std::invalid_argument("Array dimensions must be positive");
     }
     data = new T[rows * cols];
 }
 
 /**
  * Copy constructor implementation
  */
 template <typename T>
 Array_2D<T>::Array_2D(const Array_2D& other) : num_rows(other.num_rows), num_cols(other.num_cols) {
     data = new T[num_rows * num_cols];
     std::copy(other.data, other.data + (num_rows * num_cols), data);
 }
 
 /**
  * Move constructor implementation
  */
 template <typename T>
 Array_2D<T>::Array_2D(Array_2D&& other) noexcept : num_rows(other.num_rows), num_cols(other.num_cols), data(other.data) {
     other.data = nullptr;
     other.num_rows = 0;
     other.num_cols = 0;
 }
 
 /**
  * Destructor implementation
  */
 template <typename T>
 Array_2D<T>::~Array_2D() {
     delete[] data;
 }
 
 /**
  * Copy assignment operator implementation
  */
 template <typename T>
 Array_2D<T>& Array_2D<T>::operator=(const Array_2D& other) {
     if (this != &other) {
         delete[] data;
         num_rows = other.num_rows;
         num_cols = other.num_cols;
         data = new T[num_rows * num_cols];
         std::copy(other.data, other.data + (num_rows * num_cols), data);
     }
     return *this;
 }
 
 /**
  * Move assignment operator implementation
  */
 template <typename T>
 Array_2D<T>& Array_2D<T>::operator=(Array_2D&& other) noexcept {
     if (this != &other) {
         delete[] data;
         num_rows = other.num_rows;
         num_cols = other.num_cols;
         data = other.data;
         other.data = nullptr;
         other.num_rows = 0;
         other.num_cols = 0;
     }
     return *this;
 }
 
 /**
  * Element access operator implementation
  */
 template <typename T>
 T& Array_2D<T>::operator()(int row, int col) {
     #ifdef DEBUG
     if (row < 0 || row >= num_rows || col < 0 || col >= num_cols) {
         throw std::out_of_range("Array index out of bounds");
     }
     #endif
     return data[row * num_cols + col];
 }
 
 /**
  * Const element access operator implementation
  */
 template <typename T>
 const T& Array_2D<T>::operator()(int row, int col) const {
     #ifdef DEBUG
     if (row < 0 || row >= num_rows || col < 0 || col >= num_cols) {
         throw std::out_of_range("Array index out of bounds");
     }
     #endif
     return data[row * num_cols + col];
 }
 
 /**
  * Fill method implementation
  */
 template <typename T>
 void Array_2D<T>::fill(const T& value) {
     std::fill(data, data + (num_rows * num_cols), value);
 }
 
 /**
  * Swap method implementation
  */
 template <typename T>
 void Array_2D<T>::swap(Array_2D& other) noexcept {
     std::swap(num_rows, other.num_rows);
     std::swap(num_cols, other.num_cols);
     std::swap(data, other.data);
 }
 
 /**
  * Get number of rows implementation
  */
 template <typename T>
 int Array_2D<T>::rows() const {
     return num_rows;
 }
 
 /**
  * Get number of columns implementation
  */
 template <typename T>
 int Array_2D<T>::cols() const {
     return num_cols;
 }
 
 /**
  * Get data pointer implementation
  */
 template <typename T>
 T* Array_2D<T>::getData() {
     return data;
 }
 
 /**
  * Get const data pointer implementation
  */
 template <typename T>
 const T* Array_2D<T>::getData() const {
     return data;
 }