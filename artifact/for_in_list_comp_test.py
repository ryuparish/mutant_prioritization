myList = [[1,2,3], [4,5,6], [7,8,9]]


# nested for loop in list comprehension
#
# [innerItem for innerList in outList for innerItem in innerList]
#
# Same as doing:
#
#  [
#    for innerList in outList:
#        for innerItem in innerList:
#            return innerItem
#  ]
print(f"Packed array: {myList}")
print(f"Unpacked array: {[number for innerList in myList for number in innerList]}")
